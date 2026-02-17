import Foundation
import Domain

public final class GameEngine {
  public var state: GameState
  public var events: [MoveEvent]
  private let signatureVerifier: any CommandSignatureVerifying
  private var knownCommands: [UUID: MoveEvent]
  private var usedNonces: [PlayerID: Set<Int64>]
  private var rateLimit: [String: (window: Int, count: Int)]
  private let maxSubmitPerSec: Int

  public init(
    state: GameState,
    signatureVerifier: any CommandSignatureVerifying = PermissiveCommandSignatureVerifier(),
    maxSubmitPerSec: Int = 20
  ) {
    self.state = state
    self.events = []
    self.signatureVerifier = signatureVerifier
    self.knownCommands = [:]
    self.usedNonces = [:]
    self.rateLimit = [:]
    self.maxSubmitPerSec = maxSubmitPerSec
  }

  public func submit(_ command: GameCommand, at now: Date = .init()) -> GameSubmitStatus {
    let context = CommandValidator.ValidationContext(
      state: state,
      signatureVerifier: signatureVerifier,
      usedNonces: usedNonces,
      knownCommands: knownCommands,
      rateLimit: rateLimit,
      maxSubmitPerSec: maxSubmitPerSec
    )
    let validation = CommandValidator.validate(command, context: context, now: now)
    switch validation {
    case let .earlyReturn(status, updatedRateLimit):
      rateLimit = updatedRateLimit
      switch status {
      case .rejected(let s, .rateLimit, _):
        state = s
        return status
      case .rejected(let s, .invalidSignature, _):
        state = s
        return status
      case .queued:
        let from = min(state.expectedSeq, command.expectedSeq)
        let to = max(state.expectedSeq, command.expectedSeq)
        GapManager.registerGap(from: max(0, from), to: max(0, to), now: now, state: &state)
        let queuedRange: ClosedRange<Int> = max(0, from)...max(0, to)
        return .queued(state, queuedRange)
      default:
        return status
      }
    case let .proceed(updatedRateLimit):
      rateLimit = updatedRateLimit
    }

    let before = state
    var next = state
    let applyResult: SubmitRejectReason?
    switch command.action {
    case .pass:
      applyResult = next.apply(action: .pass, by: command.playerId)
    case let .place(pieceId: pieceId, variantId: variantId, origin: origin):
      applyResult = next.apply(action: .place(pieceId: pieceId, variantId: variantId, origin: origin), by: command.playerId)
    }
    guard applyResult == nil else {
      return .rejected(state, applyResult!, retryable: false)
    }

    let nextChain = state.stateHashChain.lastChainHash
    let afterFingerprint = next.computeStateFingerprint()
    let event = MoveEvent(
      eventId: UUID(),
      commandId: command.commandId,
      commandFingerprint: command.commandFingerprintV4,
      expectedSeq: command.expectedSeq,
      coordinationSeq: next.coordinationSeq,
      coordinationAuthorityId: state.authority.coordinationAuthorityId,
      source: .local,
      playerId: command.playerId,
      payload: command.action,
      stateFingerprintBefore: before.stateFingerprint,
      stateFingerprintAfter: afterFingerprint,
      status: .committed,
      chainHash: "",
      prevChainHash: nextChain,
      createdAt: now
    )
    let eventChain = computeChainHash(event, afterFingerprint: afterFingerprint)
    next.stateHashChain.prevChainHash = nextChain
    next.stateHashChain.lastChainHash = eventChain
    next.lastAppliedEventId = event.eventId
    next.snapshotSeq = next.coordinationSeq
    next.stateFingerprint = afterFingerprint
    state = next
    state.repairContext.retryCount = 0
    state.repairContext.consecutiveFailureCount = 0
    state.eventGaps = []

    knownCommands[command.commandId] = MoveEvent(
      eventId: event.eventId,
      commandId: event.commandId,
      commandFingerprint: event.commandFingerprint,
      expectedSeq: event.expectedSeq,
      coordinationSeq: event.coordinationSeq,
      coordinationAuthorityId: event.coordinationAuthorityId,
      source: event.source,
      playerId: event.playerId,
      payload: event.payload,
      stateFingerprintBefore: event.stateFingerprintBefore,
      stateFingerprintAfter: event.stateFingerprintAfter,
      status: .committed,
      chainHash: eventChain,
      prevChainHash: event.prevChainHash,
      createdAt: event.createdAt
    )

    let committed = knownCommands[command.commandId]
    if let _ = committed {
      events.append(MoveEvent(
        eventId: events.count == Int.max ? UUID() : UUID(),
        commandId: command.commandId,
        commandFingerprint: command.commandFingerprintV4,
        expectedSeq: command.expectedSeq,
        coordinationSeq: next.coordinationSeq,
        coordinationAuthorityId: state.authority.coordinationAuthorityId,
        source: .local,
        playerId: command.playerId,
        payload: command.action,
        stateFingerprintBefore: before.stateFingerprint,
        stateFingerprintAfter: afterFingerprint,
        status: .committed,
        chainHash: eventChain,
        prevChainHash: nextChain,
        createdAt: now
      ))
    }
    usedNonces[command.playerId, default: []].insert(command.nonce)
    return .accepted(state)
  }

  public func computeChainHash(_ event: MoveEvent, afterFingerprint: String) -> String {
    var writer = CanonicalWriter()
    writer.appendString(event.prevChainHash)
    writer.appendString(event.stateFingerprintBefore)
    writer.appendString(afterFingerprint)
    writer.appendData(event.commandFingerprint)
    writer.appendUInt32(UInt32(event.coordinationSeq))
    writer.appendUInt32(UInt32(event.expectedSeq))
    writer.appendString(event.coordinationAuthorityId.rawValue)
    writer.appendString(event.playerId.rawValue)
    return writer.data.sha256().hexString
  }

  public func replay(events sourceEvents: [MoveEvent]) -> RecoveryResult {
    EventReplayService.replay(
      events: sourceEvents,
      from: state,
      chainHashComputer: computeChainHash
    )
  }

  public func tick(now: Date = .init()) {
    GapManager.tick(state: &state, now: now)
  }
}
