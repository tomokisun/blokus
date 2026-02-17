import Foundation
import SQLite3

// MARK: - Schema Migration

extension PersistenceStore {
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
}
