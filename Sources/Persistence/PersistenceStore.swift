import Foundation
import SQLite3
import Domain
import Engine

private let sqliteTransient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class PersistenceStore {
  private static let defaultTargetSchemaVersion = 1
  public static var targetSchemaVersion: Int {
    #if DEBUG
    return debugTargetSchemaVersionOverride ?? defaultTargetSchemaVersion
    #else
    return defaultTargetSchemaVersion
    #endif
  }

  #if DEBUG
  nonisolated(unsafe) public static var debugTargetSchemaVersionOverride: Int?
  public static func debugSetTargetSchemaVersion(_ version: Int?) {
    debugTargetSchemaVersionOverride = version
  }

  nonisolated(unsafe) public static var debugReadOnlyOpenError: StoreError?
  public static func debugSetReadOnlyOpenError(_ error: StoreError?) {
    debugReadOnlyOpenError = error
  }
  #endif

  private var db: OpaquePointer?
  public private(set) var isReadOnly: Bool
  public private(set) var bootstrapError: StoreError?
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  #if DEBUG
  public var debugSubmitAuditForceNilDetails = false
  public var debugExecuteStepResultOverride: Int32?
  public func debugSetBootstrapError(_ error: StoreError?) {
    bootstrapError = error
  }
  #endif

  public init(path: String, fallbackReadOnlyOnMigrationFailure: Bool = false) throws {
    self.isReadOnly = false
    self.bootstrapError = nil
    self.decoder = {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return decoder
    }()
    self.encoder = {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      return encoder
    }()

    var raw: OpaquePointer?
    if sqlite3_open_v2(
      path,
      &raw,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
      nil
    ) != SQLITE_OK {
      throw StoreError.openFailed("Cannot open database: \(path)")
    }
    db = raw

    do {
      try migrateSchema()
    } catch let error as StoreError {
      guard fallbackReadOnlyOnMigrationFailure else { throw error }
      sqlite3_close_v2(raw)
      db = nil
      bootstrapError = error
      isReadOnly = true
      #if DEBUG
      if let readOnlyError = Self.debugReadOnlyOpenError {
        Self.debugReadOnlyOpenError = nil
        throw readOnlyError
      }
      #endif

      if sqlite3_open_v2(
        path,
        &raw,
        SQLITE_OPEN_READONLY,
        nil
      ) != SQLITE_OK {
        throw error
      }
      db = raw
    } catch {
      throw error
    }
  }

  deinit {
    if let db { sqlite3_close_v2(db) }
  }

  public func bootstrap() throws {
    try executeBatch([
      "PRAGMA foreign_keys = ON;",
      "PRAGMA journal_mode = WAL;",
      "PRAGMA busy_timeout = 5000;",
      """
      CREATE TABLE IF NOT EXISTS games (
        game_id TEXT PRIMARY KEY,
        state_json TEXT NOT NULL,
        snapshot_seq INTEGER NOT NULL,
        expected_seq INTEGER NOT NULL,
        coordination_seq INTEGER NOT NULL,
        state_hash TEXT,
        authority_id TEXT NOT NULL,
        coordination_epoch INTEGER NOT NULL,
        phase TEXT NOT NULL,
        repair_state TEXT,
        updated_at INTEGER NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS events (
        event_id TEXT PRIMARY KEY,
        game_id TEXT NOT NULL,
        coordination_seq INTEGER NOT NULL,
        command_id TEXT NOT NULL,
        expected_seq INTEGER NOT NULL,
        status TEXT NOT NULL,
        source TEXT NOT NULL,
        source_client_id TEXT,
        player_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        state_fp_before TEXT NOT NULL,
        state_fp_after TEXT NOT NULL,
        command_hash TEXT,
        chain_hash TEXT,
        prev_chain_hash TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE(game_id, command_id),
        UNIQUE(game_id, coordination_seq),
        FOREIGN KEY(game_id) REFERENCES games(game_id) ON DELETE CASCADE
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS inbox_events (
        id TEXT PRIMARY KEY,
        game_id TEXT NOT NULL,
        command_id TEXT NOT NULL,
        coordination_seq INTEGER,
        expected_seq INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        state TEXT NOT NULL,
        UNIQUE(game_id, command_id),
        FOREIGN KEY(game_id) REFERENCES games(game_id) ON DELETE CASCADE
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS event_gaps (
        game_id TEXT NOT NULL,
        from_seq INTEGER NOT NULL,
        to_seq INTEGER NOT NULL,
        detected_at INTEGER NOT NULL,
        retry_count INTEGER NOT NULL,
        next_retry_at INTEGER NOT NULL,
        last_error TEXT,
        max_retries INTEGER NOT NULL,
        deadline_at INTEGER NOT NULL,
        PRIMARY KEY(game_id, from_seq, to_seq),
        FOREIGN KEY(game_id) REFERENCES games(game_id) ON DELETE CASCADE
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS orphan_events (
        game_id TEXT NOT NULL,
        event_id TEXT PRIMARY KEY,
        reason TEXT NOT NULL,
        first_seen_at INTEGER NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_retry_at INTEGER,
        payload_json TEXT NOT NULL,
        FOREIGN KEY(game_id) REFERENCES games(game_id) ON DELETE CASCADE
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS schema_migrations (
        game_id TEXT NOT NULL,
        from_version INTEGER NOT NULL,
        to_version INTEGER NOT NULL,
        migrated_at INTEGER NOT NULL,
        migration_state TEXT NOT NULL,
        PRIMARY KEY(game_id, from_version, to_version)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        game_id TEXT NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(game_id) REFERENCES games(game_id) ON DELETE CASCADE
      );
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_games_phase_updated
      ON games(phase, updated_at);
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_events_game_seq
      ON events(game_id, coordination_seq);
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_events_game_status
      ON events(game_id, status);
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_inbox_game_state
      ON inbox_events(game_id, state);
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_orphan_game
      ON orphan_events(game_id);
      """
    ])
    try setUserVersion(Self.targetSchemaVersion)
    try execute("INSERT OR REPLACE INTO schema_migrations(game_id, from_version, to_version, migrated_at, migration_state) VALUES ('global', 0, 1, ?, 'done');") { statement in
      sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
    }
  }

  public func migrateSchema() throws {
    let current = try userVersion()
    if current == 0 {
      try migrate(from: current, to: Self.targetSchemaVersion)
      return
    }
    if current == Self.targetSchemaVersion { return }
    if current > Self.targetSchemaVersion {
      throw StoreError.migrationFailed(from: current, to: Self.targetSchemaVersion, reason: "newer schema")
    }
    // This project has a single migration target in this phase.
    for from in current..<Self.targetSchemaVersion {
      let to = from + 1
      try migrate(from: from, to: to)
    }
  }

  private func migrate(from: Int, to: Int) throws {
    guard from == 0 && to == 1 else {
      throw StoreError.migrationFailed(from: from, to: to, reason: "unsupported migration")
    }
    try bootstrap()
  }

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

  private func executeBatch(_ statements: [String]) throws {
    guard let db else { throw StoreError.openFailed("db closed") }
    for statement in statements {
      if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
        throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  private func execute(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws {
    guard let db else { throw StoreError.openFailed("db closed") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind {
      bind(statement!)
    }
    #if DEBUG
    let rc = debugExecuteStepResultOverride ?? sqlite3_step(statement)
    #else
    let rc = sqlite3_step(statement)
    #endif
    if rc != SQLITE_DONE && rc != SQLITE_ROW {
      throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
    }
  }

  private func query<T>(
    _ sql: String,
    bind: ((OpaquePointer) -> Void)? = nil,
    map: (OpaquePointer) throws -> T?
  ) throws -> [T] {
    guard let db else { throw StoreError.openFailed("db closed") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind { bind(statement!) }
    var rows: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let value = try map(statement!) {
        rows.append(value)
      }
    }
    return rows
  }

  private func queryFirstColumn(
    sql: String,
    bind: ((OpaquePointer) -> Void)? = nil
  ) throws -> String? {
    let rows = try query(sql, bind: bind) { statement in
      if let c = sqlite3_column_text(statement, 0) {
        return String(cString: c)
      }
      return nil
    }
    return rows.first
  }

  private func queryInt(_ sql: String, gameId: String) throws -> Int64 {
    let rows = try query(sql, bind: { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    }) { statement in
      sqlite3_column_int64(statement, 0)
    }
    return rows.first ?? 0
  }

  private func getNullableColumn<T>( _ statement: OpaquePointer, index: Int32) throws -> T? {
    if sqlite3_column_type(statement, index) == SQLITE_NULL {
      return nil
    }
    if T.self == String.self {
      guard let text = sqlite3_column_text(statement, index) else { return nil }
      return String(cString: text) as? T
    }
    return nil
  }

  #if DEBUG
  public func debugReadNullableInt(sql: String) throws -> Int? {
    let values = try query(sql, bind: nil) { statement in
      try getNullableColumn(statement, index: 0) as Int?
    }
    return values.first
  }
  #endif

  private func userVersion() throws -> Int {
    let rows = try query("PRAGMA user_version;") { _ in } map: { statement in
      Int64(sqlite3_column_int64(statement, 0))
    }
    return Int(rows.first ?? 0)
  }

  private func setUserVersion(_ version: Int) throws {
    try execute("PRAGMA user_version = \(version);")
  }

  func encodeDetails(_ values: [String: String]) -> String? {
    let sanitized = Dictionary(uniqueKeysWithValues: values.filter { !$0.value.isEmpty }.map { key, value in
      (key, value.trimmingCharacters(in: .whitespacesAndNewlines))
    })
    guard !sanitized.isEmpty else { return nil }
    guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: []) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
