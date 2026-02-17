import Foundation
import SQLite3
import Testing
#if canImport(SwiftUI)
import SwiftUI
#endif
import Domain
import Engine
import Persistence
import Connector
import DesignSystem
import Features

let sqlite3Transient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Suite(.serialized)
struct AppBaseSuite {}

let defaultDate = Date(timeIntervalSince1970: 1_700_000_000)

func newEngine(
  players: [PlayerID] = [.blue, .yellow, .red],
  verifier: any CommandSignatureVerifying = PermissiveCommandSignatureVerifier(),
  maxSubmitPerSec: Int = 20
) -> GameEngine {
  let state = GameState(gameId: "GAME-001", players: players, authorityId: .blue)
  return GameEngine(state: state, signatureVerifier: verifier, maxSubmitPerSec: maxSubmitPerSec)
}

func signedCommand(
  commandId: UUID,
  clientId: String,
  expectedSeq: Int,
  playerId: PlayerID,
  action: CommandAction,
  gameId: String = "GAME-001",
  key: String = "secret",
  issuedAt: Date = defaultDate,
  issuedNanos: Int64 = 1,
  nonce: Int64 = 1000,
  verifier: DefaultCommandSignatureVerifier? = nil
) -> GameCommand {
  if verifier != nil {
    let draft = GameCommand(
      commandId: commandId,
      clientId: clientId,
      expectedSeq: expectedSeq,
      playerId: playerId,
      action: action,
      gameId: gameId,
      schemaVersion: GameState.schemaVersion,
      rulesVersion: GameState.rulesVersion,
      pieceSetVersion: PieceLibrary.currentVersion,
      issuedAt: issuedAt,
      issuedNanos: issuedNanos,
      nonce: nonce,
      authSig: ""
    )
    let sig = DefaultCommandSignatureVerifier.signature(for: draft, key: key)
    return GameCommand(
      commandId: commandId,
      clientId: clientId,
      expectedSeq: expectedSeq,
      playerId: playerId,
      action: action,
      gameId: gameId,
      schemaVersion: GameState.schemaVersion,
      rulesVersion: GameState.rulesVersion,
      pieceSetVersion: PieceLibrary.currentVersion,
      issuedAt: issuedAt,
      issuedNanos: issuedNanos,
      nonce: nonce,
      authSig: sig
    )
  }
  return GameCommand(
    commandId: commandId,
    clientId: clientId,
    expectedSeq: expectedSeq,
    playerId: playerId,
    action: action,
    gameId: gameId,
    schemaVersion: GameState.schemaVersion,
    rulesVersion: GameState.rulesVersion,
    pieceSetVersion: PieceLibrary.currentVersion,
    issuedAt: issuedAt,
    issuedNanos: issuedNanos,
    nonce: nonce,
    authSig: "noop"
  )
}

func tempDatabasePath(_ suffix: String) -> String {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("GameTests-\(suffix)-\(UUID().uuidString).sqlite3")
  return path.path
}

func withSQLite<T>(_ path: String, _ body: (OpaquePointer) throws -> T) throws -> T {
  var db: OpaquePointer?
  if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
    throw StoreError.openFailed("Cannot open database")
  }
  defer { if let db { sqlite3_close_v2(db) } }
  return try body(db!)
}

func setUserVersion(_ path: String, _ version: Int) throws {
  try withSQLite(path) { db in
    try executeSQL(db: db, "PRAGMA user_version = \(version);")
  }
}

func executeSQL(db: OpaquePointer, _ sql: String) throws {
  if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
    let message = String(cString: sqlite3_errmsg(db))
    throw StoreError.executionFailed(message)
  }
}

func queryInt64(_ path: String, _ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> Int64 {
  try withSQLite(path) { db in
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind {
      try bind(statement!)
    }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return sqlite3_column_int64(statement, 0)
  }
}

func queryText(_ path: String, _ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> String? {
  try withSQLite(path) { db in
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind {
      try bind(statement!)
    }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    guard let raw = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: raw)
  }
}
