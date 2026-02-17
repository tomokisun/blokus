import Foundation
import Domain

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

  func appendReadOnlyEnteredAudit(
    gameId: String,
    state: GameState,
    latestGap: EventGap
  ) throws {
    let details = encodeDetails([
      "gameId": gameId,
      "coordinationSeq": "\(state.coordinationSeq)",
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

  func appendRepairTimeoutAudit(
    gameId: String,
    from: GamePhase,
    to: GamePhase,
    coordinationSeq: Int
  ) throws {
    let phaseDetails = encodeDetails([
      "from": from.rawValue,
      "to": to.rawValue,
      "coordinationSeq": "\(coordinationSeq)"
    ])
    try appendAuditLog(SQLiteAuditLog(
      gameId: gameId,
      level: "error",
      category: "repair",
      message: "repair_timeout_enter_read_only",
      details: phaseDetails
    ))
  }

}
