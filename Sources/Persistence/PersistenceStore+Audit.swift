import Foundation
import Domain
import Engine

public extension PersistenceStore {
  func appendSubmitAudit(
    gameId: String,
    command: GameCommand,
    state: GameState,
    phase: GamePhase,
    status: GameSubmitStatus
  ) throws {
    let commandFingerprint = command.commandFingerprintV4.hex
    var details: [String: String] = [
      "gameId": gameId,
      "commandId": command.commandId.uuidString,
      "commandFingerprint": commandFingerprint,
      "phase": phase.rawValue
    ]
    let (level, message): (String, String) = {
      switch status {
      case .accepted(_):
        return ("info", "command_accepted")
      case .duplicate(_, _):
        return ("info", "command_duplicate")
      case .queued(_, _):
        return ("warn", "command_queued")
      case .rejected(_, let reason, let retryable):
        details["rejectReason"] = reason.rawValue
        details["retryable"] = retryable ? "1" : "0"
        return ("warn", "command_rejected")
      case .authorityMismatch:
        details["rejectReason"] = SubmitRejectReason.invalidAuthority.rawValue
        return ("warn", "authority_mismatch")
      }
    }()
    if !state.stateHashChain.lastChainHash.isEmpty {
      details["chainHash"] = state.stateHashChain.lastChainHash
    }

    if let detailsText = debugSubmitAuditForceNilDetails ? nil : encodeDetails(details) {
      try appendAuditLog(SQLiteAuditLog(
        gameId: gameId,
        level: level,
        category: "submit",
        message: message,
        details: detailsText
      ))
    } else {
      try appendAuditLog(SQLiteAuditLog(
        gameId: gameId,
        level: level,
        category: "submit",
        message: message,
        details: nil
      ))
    }
  }

  func appendForkAudit(
    gameId: String,
    fork: ForkEventRecord,
    chainHash: String? = nil
  ) throws {
    var details: [String: String] = [
      "gameId": gameId,
      "eventId": fork.eventId.uuidString,
      "commandId": fork.commandId.uuidString,
      "coordinationSeq": "\(fork.coordinationSeq)",
      "reason": fork.reason
    ]
    if let chainHash {
      details["chainHash"] = chainHash
    }
    let detailsText = encodeDetails(details)
    try appendAuditLog(SQLiteAuditLog(
      gameId: gameId,
      level: "error",
      category: "fork",
      message: "fork_detected",
      details: detailsText
    ))
  }

  func appendOrphanAudit(
    gameId: String,
    event: MoveEvent,
    reason: String,
    chainHash: String? = nil
  ) throws {
    var details: [String: String] = [
      "gameId": gameId,
      "eventId": event.eventId.uuidString,
      "commandId": event.commandId.uuidString,
      "reason": reason,
      "commandFingerprint": event.commandFingerprint.hex,
      "coordinationSeq": "\(event.coordinationSeq)"
    ]
    if let chainHash {
      details["chainHash"] = chainHash
    }
    let detailsText = encodeDetails(details)
    try appendAuditLog(SQLiteAuditLog(
      gameId: gameId,
      level: "warn",
      category: "orphan",
      message: "event_orphaned",
      details: detailsText
    ))
  }

  func applySubmitResult(
    _ result: GameSubmitStatus,
    command: GameCommand,
    engine: GameEngine
  ) throws {
    let gameId = command.gameId
    switch result {
    case let .accepted(state):
      guard let event = engine.events.first(where: { $0.commandId == command.commandId }) else {
        try upsertGame(state, gameId: gameId)
        try clearGaps(gameId: gameId)
        if bootstrapError != nil { return }
        try appendSubmitAudit(
          gameId: gameId,
          command: command,
          state: engine.state,
          phase: engine.state.phase,
          status: result
        )
        return
      }
      try upsertGame(state, gameId: gameId)
      try upsertEvent(event, gameId: gameId)
      try clearGaps(gameId: gameId)
    case let .queued(state, _):
      try upsertGame(state, gameId: gameId)
      try syncEventGaps(gameId: gameId, gaps: state.eventGaps)
    case let .duplicate(state, _):
      try upsertGame(state, gameId: gameId)
    case let .rejected(state, _, _):
      try upsertGame(state, gameId: gameId)
    case let .authorityMismatch(state):
      try upsertGame(state, gameId: gameId)
    }
    if bootstrapError != nil {
      return
    }
    try appendSubmitAudit(
      gameId: gameId,
      command: command,
      state: engine.state,
      phase: engine.state.phase,
      status: result
    )
  }

  func applyRemoteResult(_ result: RemoteIngestResult, engine: GameEngine) throws {
    let gameId = result.finalState.gameId
    try upsertGame(result.finalState, gameId: gameId)
    try syncEventGaps(gameId: gameId, gaps: result.finalState.eventGaps)
    let acceptedSet = Set(result.acceptedEventIds)
    for event in engine.events where acceptedSet.contains(event.eventId) {
      try upsertEvent(event, gameId: gameId)
    }
    for orphanId in result.orphanedEventIds {
      if let event = engine.events.first(where: { $0.eventId == orphanId }) {
        try appendOrphan(event: event, gameId: gameId, reason: "remote_orphan_or_fork")
        try appendOrphanAudit(
          gameId: gameId,
          event: event,
          reason: "remote_orphan_or_fork",
          chainHash: event.chainHash
        )
      }
    }
    for fork in result.forkedEvents {
      try appendForkAudit(gameId: gameId, fork: fork, chainHash: nil)
    }
    if result.phase == .readOnly {
      if let latestGap = result.finalState.eventGaps.last {
        let details = encodeDetails([
          "gameId": gameId,
          "coordinationSeq": "\(result.finalState.coordinationSeq)",
          "fromSeq": "\(latestGap.fromSeq)",
          "toSeq": "\(latestGap.toSeq)",
          "retryCount": "\(latestGap.retryCount)"
        ])
        if bootstrapError == nil {
          try appendAuditLog(SQLiteAuditLog(
            gameId: gameId,
            level: "error",
            category: "repair",
            message: "entered_read_only",
            details: details
          ))
        }
      }
    }
  }

  func persistRepairTick(gameId: String, engine: GameEngine) throws -> GamePhase {
    let before = engine.state.phase
    engine.tick()
    try upsertGame(engine.state, gameId: gameId)
    try syncEventGaps(gameId: gameId, gaps: engine.state.eventGaps)
    if before != .readOnly && engine.state.phase == .readOnly {
      let phaseDetails = encodeDetails([
        "from": before.rawValue,
        "to": engine.state.phase.rawValue,
        "coordinationSeq": "\(engine.state.coordinationSeq)"
      ])
      try appendAuditLog(SQLiteAuditLog(
        gameId: gameId,
        level: "error",
        category: "repair",
        message: "repair_timeout_enter_read_only",
        details: phaseDetails
      ))
    }
    return engine.state.phase
  }
}
