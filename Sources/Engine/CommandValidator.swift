import Foundation
import Domain

public enum CommandValidator {
  public struct ValidationContext {
    public let state: GameState
    public let signatureVerifier: any CommandSignatureVerifying
    public let usedNonces: [PlayerID: Set<Int64>]
    public let knownCommands: [UUID: MoveEvent]
    public let rateLimit: [String: (window: Int, count: Int)]
    public let maxSubmitPerSec: Int

    public init(
      state: GameState,
      signatureVerifier: any CommandSignatureVerifying,
      usedNonces: [PlayerID: Set<Int64>],
      knownCommands: [UUID: MoveEvent],
      rateLimit: [String: (window: Int, count: Int)],
      maxSubmitPerSec: Int
    ) {
      self.state = state
      self.signatureVerifier = signatureVerifier
      self.usedNonces = usedNonces
      self.knownCommands = knownCommands
      self.rateLimit = rateLimit
      self.maxSubmitPerSec = maxSubmitPerSec
    }
  }

  public enum ValidationResult {
    case proceed(updatedRateLimit: [String: (window: Int, count: Int)])
    case earlyReturn(GameSubmitStatus, updatedRateLimit: [String: (window: Int, count: Int)])
  }

  public static func validate(
    _ command: GameCommand,
    context: ValidationContext,
    now: Date
  ) -> ValidationResult {
    let nowSecond = Int(now.timeIntervalSince1970)
    var updatedRateLimit = context.rateLimit
    let limit = updatedRateLimit[command.clientId] ?? (nowSecond, 0)
    if limit.window == nowSecond {
      if limit.count >= context.maxSubmitPerSec {
        var repairedState = context.state
        repairedState.beginRepair(now)
        return .earlyReturn(.rejected(repairedState, .rateLimit, retryable: true), updatedRateLimit: context.rateLimit)
      }
      updatedRateLimit[command.clientId] = (nowSecond, limit.count + 1)
    } else {
      updatedRateLimit[command.clientId] = (nowSecond, 1)
    }

    guard context.state.gameId == command.gameId else {
      return .earlyReturn(.rejected(context.state, .schemaMismatch, retryable: false), updatedRateLimit: updatedRateLimit)
    }
    guard command.schemaVersion == GameState.schemaVersion,
          command.rulesVersion == GameState.rulesVersion,
          command.pieceSetVersion == PieceLibrary.currentVersion else {
      return .earlyReturn(.rejected(context.state, .versionMismatch, retryable: false), updatedRateLimit: updatedRateLimit)
    }
    guard context.signatureVerifier.verify(command) else {
      var repairedState = context.state
      repairedState.beginRepair(now)
      return .earlyReturn(.rejected(repairedState, .invalidSignature, retryable: false), updatedRateLimit: updatedRateLimit)
    }
    if !context.state.localAuthorityMode && command.clientId != context.state.authority.coordinationAuthorityId.rawValue {
      return .earlyReturn(.authorityMismatch(context.state), updatedRateLimit: updatedRateLimit)
    }
    if context.usedNonces[command.playerId, default: []].contains(command.nonce) {
      return .earlyReturn(.rejected(context.state, .replayOrDuplicate, retryable: false), updatedRateLimit: updatedRateLimit)
    }

    if let existing = context.knownCommands[command.commandId] {
      let expectedHash = command.commandFingerprintV4
      if existing.commandFingerprint == expectedHash {
        return .earlyReturn(.duplicate(context.state, existing.eventId), updatedRateLimit: updatedRateLimit)
      } else {
        return .earlyReturn(.rejected(context.state, .replayOrDuplicate, retryable: false), updatedRateLimit: updatedRateLimit)
      }
    }

    if command.expectedSeq != context.state.expectedSeq {
      let from = min(context.state.expectedSeq, command.expectedSeq)
      let to = max(context.state.expectedSeq, command.expectedSeq)
      let queuedRange: ClosedRange<Int> = max(0, from)...max(0, to)
      return .earlyReturn(.queued(context.state, queuedRange), updatedRateLimit: updatedRateLimit)
    }

    if context.state.activePlayerId != command.playerId && context.state.phase == .playing {
      return .earlyReturn(.rejected(context.state, .invalidTurn, retryable: false), updatedRateLimit: updatedRateLimit)
    }
    guard let _ = context.state.turnOrder.firstIndex(of: command.playerId) else {
      return .earlyReturn(.rejected(context.state, .invalidAuthority, retryable: false), updatedRateLimit: updatedRateLimit)
    }

    return .proceed(updatedRateLimit: updatedRateLimit)
  }
}
