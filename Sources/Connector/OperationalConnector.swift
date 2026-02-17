import Foundation
import Domain
import Engine
import Persistence

public enum ConnectorError: Error {
  case readOnlyMode
}

public final class OperationalConnector {
  public private(set) var engine: GameEngine
  public let store: PersistenceStore
  public let gameId: GameID

  public init(engine: GameEngine, store: PersistenceStore) {
    self.engine = engine
    self.store = store
    self.gameId = engine.state.gameId
  }

  public init(path: String, initialState: GameState, allowReadOnlyFallback: Bool = true) throws {
    let store = try PersistenceStore(path: path, fallbackReadOnlyOnMigrationFailure: allowReadOnlyFallback)
    self.store = store
    self.engine = GameEngine(state: initialState)
    self.gameId = initialState.gameId
    if store.isReadOnly {
      self.engine.state.phase = .readOnly
    }
    if !store.isReadOnly {
      try store.upsertGame(initialState, gameId: initialState.gameId)
    }
  }

  public func submit(_ command: GameCommand, at now: Date = .init()) throws -> GameSubmitStatus {
    let result = engine.submit(command, at: now)
    if store.isReadOnly {
      throw ConnectorError.readOnlyMode
    }
    try store.applySubmitResult(result, command: command, engine: engine)
    return result
  }

  public func applyRemoteEvents(_ incoming: [MoveEvent], at now: Date = .init()) throws -> RemoteIngestResult {
    let result = engine.applyRemoteEvents(incoming, at: now)
    if store.isReadOnly {
      throw ConnectorError.readOnlyMode
    }
    try store.applyRemoteResult(result, engine: engine)
    return result
  }

  public func tick(_ now: Date = .init()) throws -> GamePhase {
    if store.isReadOnly {
      return engine.state.phase
    }
    return try store.persistRepairTick(gameId: gameId, engine: engine)
  }

  public func recoverFromPersistence() throws -> RecoveryPlan {
    if store.isReadOnly {
      throw ConnectorError.readOnlyMode
    }
    let plan = try store.rebuild(gameId: gameId)
    if let restored = try store.loadGame(gameId: gameId) {
      engine = GameEngine(state: restored)
    }
    return plan
  }

  public func refreshFromStore() throws -> GameState {
    guard let loaded = try store.loadGame(gameId: gameId) else { return engine.state }
    engine = GameEngine(state: loaded)
    return loaded
  }

  public func operationalMetrics() throws -> OperationalMetrics {
    return try store.loadOperationalMetrics(gameId: gameId)
  }

  public func readOnlyContext() throws -> ReadOnlyContext? {
    return try store.readOnlyContext(gameId: gameId)
  }
}
