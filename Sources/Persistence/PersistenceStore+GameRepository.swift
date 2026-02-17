import Foundation
import SQLite3
import Domain
import Engine

// MARK: - Game State CRUD & Recovery

extension PersistenceStore {
  public func upsertGame(_ state: GameState, gameId: String) throws {
    let encoded = try encoder.encode(state)
    let json = String(data: encoded, encoding: .utf8) ?? "{}"
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    try execute(
      """
      INSERT INTO games(
        game_id, state_json, snapshot_seq, expected_seq, coordination_seq, state_hash,
        authority_id, coordination_epoch, phase, repair_state, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(game_id) DO UPDATE SET
        state_json = excluded.state_json,
        snapshot_seq = excluded.snapshot_seq,
        expected_seq = excluded.expected_seq,
        coordination_seq = excluded.coordination_seq,
        state_hash = excluded.state_hash,
        authority_id = excluded.authority_id,
        coordination_epoch = excluded.coordination_epoch,
        phase = excluded.phase,
        repair_state = excluded.repair_state,
        updated_at = excluded.updated_at;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, json, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 3, Int64(state.snapshotSeq))
      sqlite3_bind_int64(statement, 4, Int64(state.expectedSeq))
      sqlite3_bind_int64(statement, 5, Int64(state.coordinationSeq))
      sqlite3_bind_text(statement, 6, state.stateFingerprint, -1, sqliteTransient)
      sqlite3_bind_text(statement, 7, state.authority.coordinationAuthorityId.rawValue, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 8, Int64(state.authority.coordinationEpoch))
      sqlite3_bind_text(statement, 9, state.phase.rawValue, -1, sqliteTransient)
      sqlite3_bind_null(statement, 10)
      sqlite3_bind_int64(statement, 11, now)
    }
  }

  public func loadGame(gameId: String) throws -> GameState? {
    let json = try queryFirstColumn(sql: "SELECT state_json FROM games WHERE game_id = ?") { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    }

    guard let json else { return nil }
    guard let decoded = try? decoder.decode(GameState.self, from: Data(json.utf8)) else {
      throw StoreError.decodeFailed("failed to decode game state")
    }
    return decoded
  }

  public func rebuild(gameId: String) throws -> RecoveryPlan {
    guard let snapshot = try loadGame(gameId: gameId) else {
      throw StoreError.executionFailed("missing snapshot")
    }
    let committed = try loadCommittedEvents(gameId: gameId)
    let engine = GameEngine(state: snapshot)
    let result = engine.replay(events: committed)
    try upsertGame(result.restoredState, gameId: gameId)
    return RecoveryPlan(
      restoredState: result.restoredState,
      orphanedEventIds: result.orphanedEvents
    )
  }

  public func readOnlyContext(gameId: String) throws -> ReadOnlyContext? {
    guard let state = try loadGame(gameId: gameId) else { return nil }
    let gaps = try loadEventGaps(gameId: gameId)
    let repairState = try query("SELECT repair_state FROM games WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    } map: { statement in
      try getNullableColumn(statement, index: 0) as String?
    }.first
    _ = repairState
    let latestSeq = Int(try queryInt("""
      SELECT COALESCE(MAX(coordination_seq), 0)
      FROM events
      WHERE game_id = ? AND status = 'committed';
    """, gameId: gameId))
    let latestOrphan: [(UUID, String)] = try query(
      """
      SELECT event_id, reason
      FROM orphan_events
      WHERE game_id = ?
      ORDER BY first_seen_at DESC
      LIMIT 1;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    } map: { statement in
      guard let rawId = sqlite3_column_text(statement, 0) else { return nil }
      guard let eventId = UUID(uuidString: String(cString: rawId)) else { return nil }
      let reason = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? ""
      return (eventId, reason)
    }

    return ReadOnlyContext(
      gameId: gameId,
      phase: state.phase,
      openGaps: gaps,
      latestMatchedCoordinationSeq: latestSeq,
      lastSeenOrphanEventId: latestOrphan.first?.0,
      lastSeenOrphanReason: latestOrphan.first?.1,
      retryCount: gaps.map(\.retryCount).max() ?? 0,
      lastFailureAt: state.repairContext.lastFailureAt
    )
  }

  public func loadOperationalMetrics(gameId: String) throws -> OperationalMetrics {
    let gapOpenCount = try queryInt("SELECT COUNT(*) FROM event_gaps WHERE game_id = ?;", gameId: gameId)
    let queuedCount = try queryInt("SELECT COUNT(*) FROM events WHERE game_id = ? AND status = 'queued';", gameId: gameId)
    let forkCount = try queryInt("SELECT COUNT(*) FROM orphan_events WHERE game_id = ?;", gameId: gameId)
    let committedCount = try queryInt("SELECT COUNT(*) FROM events WHERE game_id = ? AND status = 'committed';", gameId: gameId)
    let orphanCount = try queryInt("SELECT COUNT(*) FROM orphan_events WHERE game_id = ?;", gameId: gameId)
    let latestRetryCount = try queryInt("SELECT COALESCE(MAX(retry_count), 0) FROM event_gaps WHERE game_id = ?;", gameId: gameId)
    let gapRecoveryDuration = try queryInt("""
      SELECT COALESCE(SUM(deadline_at - detected_at), 0)
      FROM event_gaps WHERE game_id = ?;
      """, gameId: gameId)
    let total = committedCount + orphanCount
    let orphanRate = total == 0 ? 0.0 : Double(orphanCount) / Double(total)

    return OperationalMetrics(
      gapOpenCount: gapOpenCount,
      gapRecoveryDurationMs: gapRecoveryDuration,
      queuedCount: queuedCount,
      forkCount: forkCount,
      orphanRate: orphanRate,
      latestRetryCount: latestRetryCount
    )
  }

  public func applySubmitResult(
    _ result: GameSubmitStatus,
    command: GameCommand,
    engine: GameEngine
  ) throws {
    switch result {
    case let .accepted(state):
      try upsertGame(state, gameId: command.gameId)
      if let event = engine.events.first(where: { $0.commandId == command.commandId }) {
        try upsertEvent(event, gameId: command.gameId)
      }
      try clearGaps(gameId: command.gameId)

    case let .queued(state, _):
      try upsertGame(state, gameId: command.gameId)
      try syncEventGaps(gameId: command.gameId, gaps: state.eventGaps)

    case let .duplicate(state, _):
      try upsertGame(state, gameId: command.gameId)

    case let .rejected(state, _, _):
      try upsertGame(state, gameId: command.gameId)

    case let .authorityMismatch(state):
      try upsertGame(state, gameId: command.gameId)
    }

    guard bootstrapError == nil else { return }
    try appendSubmitAudit(
      gameId: command.gameId,
      command: command,
      state: engine.state,
      phase: engine.state.phase,
      status: result
    )
  }
}
