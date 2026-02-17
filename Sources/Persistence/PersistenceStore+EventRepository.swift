import Foundation
import SQLite3
import Domain

// MARK: - Event, Gap, Orphan, Inbox & Audit CRUD

extension PersistenceStore {
  public func upsertEvent(_ event: MoveEvent, gameId: String) throws {
    let payload = try encoder.encode(event)
    let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
    try execute(
      """
      INSERT INTO events(
        event_id, game_id, coordination_seq, command_id, expected_seq, status, source,
        source_client_id, player_id, payload_json, state_fp_before, state_fp_after,
        command_hash, chain_hash, prev_chain_hash, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(game_id, command_id) DO UPDATE SET
        coordination_seq = excluded.coordination_seq,
        expected_seq = excluded.expected_seq,
        status = excluded.status,
        source = excluded.source,
        state_fp_before = excluded.state_fp_before,
        state_fp_after = excluded.state_fp_after,
        chain_hash = excluded.chain_hash,
        prev_chain_hash = excluded.prev_chain_hash,
        created_at = excluded.created_at;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, event.eventId.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, gameId, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 3, Int64(event.coordinationSeq))
      sqlite3_bind_text(statement, 4, event.commandId.uuidString, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 5, Int64(event.expectedSeq))
      sqlite3_bind_text(statement, 6, event.status.rawValue, -1, sqliteTransient)
      sqlite3_bind_text(statement, 7, event.source == .local ? "local" : "remote", -1, sqliteTransient)
      sqlite3_bind_text(statement, 8, event.playerId.rawValue, -1, sqliteTransient)
      sqlite3_bind_text(statement, 9, payloadText, -1, sqliteTransient)
      sqlite3_bind_text(statement, 10, event.stateFingerprintBefore, -1, sqliteTransient)
      sqlite3_bind_text(statement, 11, event.stateFingerprintAfter, -1, sqliteTransient)
      sqlite3_bind_text(statement, 12, event.commandFingerprint.hex, -1, sqliteTransient)
      sqlite3_bind_text(statement, 13, event.chainHash, -1, sqliteTransient)
      sqlite3_bind_text(statement, 14, event.prevChainHash, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 15, Int64(event.createdAt.timeIntervalSince1970 * 1000))
    }
  }

  public func insertGap(_ gap: EventGap, gameId: String) throws {
    try execute(
      """
      INSERT OR REPLACE INTO event_gaps(
        game_id, from_seq, to_seq, detected_at, retry_count, next_retry_at, last_error, max_retries, deadline_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 2, Int64(gap.fromSeq))
      sqlite3_bind_int64(statement, 3, Int64(gap.toSeq))
      sqlite3_bind_int64(statement, 4, Int64(gap.detectedAt.timeIntervalSince1970 * 1000))
      sqlite3_bind_int64(statement, 5, Int64(gap.retryCount))
      sqlite3_bind_int64(statement, 6, Int64(gap.nextRetryAt.timeIntervalSince1970 * 1000))
      if let error = gap.lastError {
        sqlite3_bind_text(statement, 7, error, -1, sqliteTransient)
      } else {
        sqlite3_bind_null(statement, 7)
      }
      sqlite3_bind_int64(statement, 8, Int64(gap.maxRetries))
      sqlite3_bind_int64(statement, 9, Int64(gap.deadlineAt.timeIntervalSince1970 * 1000))
    }
  }

  public func appendOrphan(event: MoveEvent, gameId: String, reason: String) throws {
    let payload = try encoder.encode(event)
    let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
    try execute(
      """
      INSERT INTO orphan_events(game_id, event_id, reason, first_seen_at, retry_count, last_retry_at, payload_json)
      VALUES (?, ?, ?, ?, 0, NULL, ?)
      ON CONFLICT(event_id) DO UPDATE SET reason = excluded.reason, first_seen_at = excluded.first_seen_at, payload_json = excluded.payload_json;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, event.eventId.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(statement, 3, reason, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970 * 1000))
      sqlite3_bind_text(statement, 5, payloadText, -1, sqliteTransient)
    }
  }

  public func clearGaps(gameId: String) throws {
    try execute("DELETE FROM event_gaps WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    }
  }

  public func loadEventGaps(gameId: String) throws -> [EventGap] {
    try query(
      """
      SELECT from_seq, to_seq, detected_at, retry_count, next_retry_at, last_error, max_retries, deadline_at
      FROM event_gaps WHERE game_id = ? ORDER BY from_seq ASC;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    } map: { statement in
      EventGap(
        fromSeq: Int(sqlite3_column_int64(statement, 0)),
        toSeq: Int(sqlite3_column_int64(statement, 1)),
        detectedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1000),
        retryCount: Int(sqlite3_column_int64(statement, 3)),
        nextRetryAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1000),
        lastError: {
          guard let c = sqlite3_column_text(statement, 5) else { return nil }
          return String(cString: c)
        }(),
        maxRetries: Int(sqlite3_column_int64(statement, 6)),
        deadlineAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 7)) / 1000)
      )
    }
  }

  public func loadCommittedEvents(gameId: String) throws -> [MoveEvent] {
    try query(
      """
      SELECT payload_json FROM events WHERE game_id = ? AND status = 'committed' ORDER BY coordination_seq ASC;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    } map: { statement in
      guard let c = sqlite3_column_text(statement, 0) else { return nil }
      let json = String(cString: c)
      return try decoder.decode(MoveEvent.self, from: Data(json.utf8))
    }
  }

  public func appendAuditLog(_ log: SQLiteAuditLog) throws {
    try execute(
      """
      INSERT INTO audit_logs(id, game_id, level, category, message, details, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?);
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, log.id.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, log.gameId, -1, sqliteTransient)
      sqlite3_bind_text(statement, 3, log.level, -1, sqliteTransient)
      sqlite3_bind_text(statement, 4, log.category, -1, sqliteTransient)
      sqlite3_bind_text(statement, 5, log.message, -1, sqliteTransient)
      if let details = log.details {
        sqlite3_bind_text(statement, 6, details, -1, sqliteTransient)
      } else {
        sqlite3_bind_null(statement, 6)
      }
      sqlite3_bind_int64(statement, 7, Int64(log.createdAt.timeIntervalSince1970 * 1000))
    }
  }

  public func syncEventGaps(gameId: String, gaps: [EventGap]) throws {
    try clearGaps(gameId: gameId)
    for gap in gaps {
      try insertGap(gap, gameId: gameId)
    }
  }

  public func appendInboxEvent(_ event: MoveEvent, gameId: String, state: String) throws {
    let payload = try encoder.encode(event)
    let payloadText = String(data: payload, encoding: .utf8) ?? "{}"
    try execute(
      """
      INSERT INTO inbox_events(id, game_id, command_id, coordination_seq, expected_seq, payload_json, received_at, state)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(game_id, command_id) DO UPDATE SET state = excluded.state, payload_json = excluded.payload_json;
      """
    ) { statement in
      sqlite3_bind_text(statement, 1, event.eventId.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(statement, 2, gameId, -1, sqliteTransient)
      sqlite3_bind_text(statement, 3, event.commandId.uuidString, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 4, Int64(event.coordinationSeq))
      sqlite3_bind_int64(statement, 5, Int64(event.expectedSeq))
      sqlite3_bind_text(statement, 6, payloadText, -1, sqliteTransient)
      sqlite3_bind_int64(statement, 7, Int64(event.createdAt.timeIntervalSince1970 * 1000))
      sqlite3_bind_text(statement, 8, state, -1, sqliteTransient)
    }
  }
}
