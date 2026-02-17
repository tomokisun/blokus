import Foundation
import SQLite3
import Testing
import Domain
import Engine
import Persistence
import Connector

extension AppBaseSuite {
  @Test
  func operationalConnectorLifecycle() throws {
    let path = tempDatabasePath("connector")
    let initial = GameState(gameId: "GAME-CONN", players: [.blue, .yellow], authorityId: .blue)
    let connector = try OperationalConnector(
      path: path,
      initialState: initial,
      allowReadOnlyFallback: true
    )
    let initialCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      key: "secret",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )
    let _ = try connector.submit(initialCommand)
    _ = try connector.applyRemoteEvents([])
    let _ = try connector.tick()
    let _ = try connector.operationalMetrics()
    let refreshed = try connector.refreshFromStore()
    #expect(refreshed.gameId == initial.gameId)

    let roState = try connector.readOnlyContext()
    _ = roState
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func operationalConnectorReadOnlyFlow() throws {
    let path = tempDatabasePath("connector-readonly")
    try setUserVersion(path, 3)
    let initial = GameState(gameId: "GAME-CONN-RO", players: [.blue, .yellow], authorityId: .blue)
    let connector = try OperationalConnector(path: path, initialState: initial)
    #expect(connector.store.isReadOnly)
    #expect(try connector.tick() == .readOnly)
    do {
      _ = try connector.submit(signedCommand(commandId: UUID(), clientId: "A", expectedSeq: 0, playerId: .blue, action: .pass))
      Issue.record("read-only store must reject submit")
    } catch ConnectorError.readOnlyMode {}

    do {
      _ = try connector.applyRemoteEvents([])
      Issue.record("read-only store must reject applyRemoteEvents")
    } catch ConnectorError.readOnlyMode {}
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func operationalConnectorInitEngineStyle() throws {
    let path = tempDatabasePath("connector-engine-init")
    let store = try PersistenceStore(path: path)
    let initial = GameState(gameId: "GAME-CONN-INIT", players: [.blue, .yellow], authorityId: .blue)
    let engine = GameEngine(state: initial, signatureVerifier: PermissiveCommandSignatureVerifier())
    let connector = OperationalConnector(engine: engine, store: store)
    #expect(connector.gameId == initial.gameId)

    var readOnlyGame = initial
    readOnlyGame.phase = .readOnly
    try store.upsertGame(readOnlyGame, gameId: readOnlyGame.gameId)
    try withSQLite(path) { db in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, "UPDATE games SET repair_state = ? WHERE game_id = ?;", -1, &statement, nil) == SQLITE_OK else {
        throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(statement, 1, "{\"repair\":\"test\"}", -1, sqlite3Transient)
      sqlite3_bind_text(statement, 2, readOnlyGame.gameId, -1, sqlite3Transient)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
      }
    }
    let context = try connector.readOnlyContext()
    #expect(context?.phase == .readOnly)
    #expect(context?.gameId == readOnlyGame.gameId)

    try FileManager.default.removeItem(atPath: path)
  }
}
