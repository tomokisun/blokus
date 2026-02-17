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
    let gameId = command.gameId
    switch result {
    case let .accepted(state):
      guard let event = engine.events.first(where: { $0.commandId == command.commandId }) else {
        try store.upsertGame(state, gameId: gameId)
        try store.clearGaps(gameId: gameId)
        if store.bootstrapError != nil { return result }
        try store.appendSubmitAudit(
          gameId: gameId,
          command: command,
          state: engine.state,
          phase: engine.state.phase,
          status: result
        )
        return result
      }
      try store.upsertGame(state, gameId: gameId)
      try store.upsertEvent(event, gameId: gameId)
      try store.clearGaps(gameId: gameId)
    case let .queued(state, _):
      try store.upsertGame(state, gameId: gameId)
      try store.syncEventGaps(gameId: gameId, gaps: state.eventGaps)
    case let .duplicate(state, _):
      try store.upsertGame(state, gameId: gameId)
    case let .rejected(state, _, _):
      try store.upsertGame(state, gameId: gameId)
    case let .authorityMismatch(state):
      try store.upsertGame(state, gameId: gameId)
    }
    if store.bootstrapError != nil {
      return result
    }
    try store.appendSubmitAudit(
      gameId: gameId,
      command: command,
      state: engine.state,
      phase: engine.state.phase,
      status: result
    )
    return result
  }

  public func applyRemoteEvents(_ incoming: [MoveEvent], at now: Date = .init()) throws -> RemoteIngestResult {
    let result = engine.applyRemoteEvents(incoming, at: now)
    if store.isReadOnly {
      throw ConnectorError.readOnlyMode
    }
    let gameId = result.finalState.gameId
    try store.upsertGame(result.finalState, gameId: gameId)
    try store.syncEventGaps(gameId: gameId, gaps: result.finalState.eventGaps)
    for event in result.committedEvents {
      try store.upsertEvent(event, gameId: gameId)
    }
    for orphanId in result.orphanedEventIds {
      if let event = engine.events.first(where: { $0.eventId == orphanId }) {
        try store.appendOrphan(event: event, gameId: gameId, reason: "remote_orphan_or_fork")
        try store.appendOrphanAudit(
          gameId: gameId,
          event: event,
          reason: "remote_orphan_or_fork",
          chainHash: event.chainHash
        )
      }
    }
    for fork in result.forkedEvents {
      try store.appendForkAudit(gameId: gameId, fork: fork, chainHash: nil)
    }
    if result.phase == .readOnly {
      if let latestGap = result.finalState.eventGaps.last {
        try store.appendReadOnlyEnteredAudit(
          gameId: gameId,
          state: result.finalState,
          latestGap: latestGap
        )
      }
    }
    return result
  }

  public func tick(_ now: Date = .init()) throws -> GamePhase {
    if store.isReadOnly {
      return engine.state.phase
    }
    let before = engine.state.phase
    engine.tick()
    try store.upsertGame(engine.state, gameId: gameId)
    try store.syncEventGaps(gameId: gameId, gaps: engine.state.eventGaps)
    if before != .readOnly && engine.state.phase == .readOnly {
      try store.appendRepairTimeoutAudit(
        gameId: gameId,
        from: before,
        to: engine.state.phase,
        coordinationSeq: engine.state.coordinationSeq
      )
    }
    return engine.state.phase
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
