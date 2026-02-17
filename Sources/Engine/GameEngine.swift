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
    let nowSecond = Int(now.timeIntervalSince1970)
    let limit = rateLimit[command.clientId] ?? (nowSecond, 0)
    if limit.window == nowSecond {
      if limit.count >= maxSubmitPerSec {
        state.beginRepair(now)
        return .rejected(state, .rateLimit, retryable: true)
      }
      rateLimit[command.clientId] = (nowSecond, limit.count + 1)
    } else {
      rateLimit[command.clientId] = (nowSecond, 1)
    }

    guard state.gameId == command.gameId else {
      return .rejected(state, .schemaMismatch, retryable: false)
    }
    guard command.schemaVersion == GameState.schemaVersion,
          command.rulesVersion == GameState.rulesVersion,
          command.pieceSetVersion == PieceLibrary.currentVersion else {
      return .rejected(state, .versionMismatch, retryable: false)
    }
    guard signatureVerifier.verify(command) else {
      state.beginRepair(now)
      return .rejected(state, .invalidSignature, retryable: false)
    }
    if !state.localAuthorityMode && command.clientId != state.authority.coordinationAuthorityId.rawValue {
      return .authorityMismatch(state)
    }
    if usedNonces[command.playerId, default: []].contains(command.nonce) {
      return .rejected(state, .replayOrDuplicate, retryable: false)
    }

    if let existing = knownCommands[command.commandId] {
      let expectedHash = command.commandFingerprintV4
      if existing.commandFingerprint == expectedHash {
        return .duplicate(state, existing.eventId)
      } else {
        return .rejected(state, .replayOrDuplicate, retryable: false)
      }
    }

    if command.expectedSeq != state.expectedSeq {
      let from = min(state.expectedSeq, command.expectedSeq)
      let to = max(state.expectedSeq, command.expectedSeq)
      let queuedRange: ClosedRange<Int> = max(0, from)...max(0, to)
      registerGap(from: queuedRange.lowerBound, to: queuedRange.upperBound, now: now)
      return .queued(state, queuedRange)
    }

    if state.activePlayerId != command.playerId && state.phase == .playing {
      return .rejected(state, .invalidTurn, retryable: false)
    }
    guard let _ = state.turnOrder.firstIndex(of: command.playerId) else {
      return .rejected(state, .invalidAuthority, retryable: false)
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
    var restored = state
    var orphans: [UUID] = []
    let sorted = sourceEvents.sorted { lhs, rhs in
      if lhs.coordinationSeq != rhs.coordinationSeq { return lhs.coordinationSeq < rhs.coordinationSeq }
      return lhs.createdAt < rhs.createdAt
    }
    for event in sorted {
      if event.status != .committed { continue }
      if event.coordinationSeq != restored.coordinationSeq + 1 {
        orphans.append(event.eventId)
        continue
      }
      _ = MoveEvent(
        eventId: event.eventId,
        commandId: event.commandId,
        commandFingerprint: event.commandFingerprint,
        expectedSeq: event.expectedSeq,
        coordinationSeq: event.coordinationSeq,
        coordinationAuthorityId: event.coordinationAuthorityId,
        source: event.source,
        playerId: event.playerId,
        payload: event.payload,
        stateFingerprintBefore: restored.stateFingerprint,
        stateFingerprintAfter: "",
        status: event.status,
        chainHash: "",
        prevChainHash: restored.stateHashChain.lastChainHash,
        createdAt: event.createdAt
      )
      let previewAfter = applyDuringReplay(
        action: event.payload,
        playerId: event.playerId,
        expectedBefore: restored,
        source: event
      )
      guard let applyResult = previewAfter else {
        orphans.append(event.eventId)
        continue
      }
      let (nextState, nextAfter, chainHash) = applyResult
      if chainHash != event.expectedChainHash() {
        orphans.append(event.eventId)
        restored.beginRepair(event.createdAt)
        continue
      }
      if nextAfter != event.stateFingerprintAfter {
        orphans.append(event.eventId)
        restored.beginRepair(event.createdAt)
        continue
      }
      restored = nextState
      restored.stateFingerprint = nextAfter
      restored.stateHashChain = StateHashChain(prevChainHash: restored.stateHashChain.lastChainHash, lastChainHash: chainHash)
    }
    restored.eventGaps = []
    if restored.phase != .finished {
      restored.phase = .playing
    }
    return RecoveryResult(restoredState: restored, orphanedEvents: orphans)
  }

  private func applyDuringReplay(
    action: CommandAction,
    playerId: PlayerID,
    expectedBefore: GameState,
    source: MoveEvent
  ) -> (GameState, String, String)? {
    var next = expectedBefore
    if validateReplayPrecondition(action: action, playerId: playerId, in: next) != nil {
      return nil
    }

    let beforeFingerprint = next.stateFingerprint
    guard next.apply(action: action, by: playerId) == nil else { return nil }
    let afterFingerprint = next.stateFingerprint
    let writerEvent = MoveEvent(
      eventId: source.eventId,
      commandId: source.commandId,
      commandFingerprint: source.commandFingerprint,
      expectedSeq: source.expectedSeq,
      coordinationSeq: source.coordinationSeq,
      coordinationAuthorityId: source.coordinationAuthorityId,
      source: source.source,
      playerId: source.playerId,
      payload: action,
      stateFingerprintBefore: beforeFingerprint,
      stateFingerprintAfter: afterFingerprint,
      status: source.status,
      chainHash: "",
      prevChainHash: next.stateHashChain.lastChainHash,
      createdAt: source.createdAt
    )
    let chainHash = computeChainHash(writerEvent, afterFingerprint: afterFingerprint)
    return (next, afterFingerprint, chainHash)
  }

  private func validateReplayPrecondition(
    action: CommandAction,
    playerId: PlayerID,
    in state: GameState
  ) -> SubmitRejectReason? {
    if state.turnOrder.firstIndex(of: playerId) == nil { return .invalidAuthority }
    if !state.localAuthorityMode {
      return nil
    }
    if action == .pass && state.hasAnyLegalMove(for: playerId) { return .illegalPass }
    return nil
  }

  public func tick(now: Date = .init()) {
    guard !state.eventGaps.isEmpty else { return }
    for idx in state.eventGaps.indices {
      if now >= state.eventGaps[idx].nextRetryAt {
        state.eventGaps[idx].retryCount += 1
        if state.eventGaps[idx].retryCount >= state.eventGaps[idx].maxRetries || now >= state.eventGaps[idx].deadlineAt {
          state.beginReadOnly(now)
          return
        }
        let delay = retryDelay(for: state.eventGaps[idx].retryCount)
        state.eventGaps[idx].nextRetryAt = now.addingTimeInterval(delay)
      }
    }
    if state.phase == .readOnly { return }
    state.phase = .repair
  }

  private func registerGap(from: Int, to: Int, now: Date) {
    let nowFrom = max(0, min(from, to))
    let nowTo = max(nowFrom, max(0, max(from, to)))
    let requested = EventGap(
      fromSeq: nowFrom,
      toSeq: nowTo,
      detectedAt: now,
      retryCount: 0,
      nextRetryAt: now.addingTimeInterval(1),
      lastError: "sequence_gap",
      maxRetries: 5,
      deadlineAt: now.addingTimeInterval(31)
    )

    if let index = state.eventGaps.firstIndex(where: { existing in
      existing.toSeq + 1 >= requested.fromSeq && requested.toSeq + 1 >= existing.fromSeq
    }) {
      state.eventGaps[index].fromSeq = min(state.eventGaps[index].fromSeq, requested.fromSeq)
      state.eventGaps[index].toSeq = max(state.eventGaps[index].toSeq, requested.toSeq)
      state.eventGaps[index].detectedAt = requested.detectedAt
      state.eventGaps[index].nextRetryAt = requested.nextRetryAt
      return
    }

    state.eventGaps.append(requested)
    state.eventGaps.sort { $0.fromSeq < $1.fromSeq }
    state.beginRepair(now)
  }

  private func retryDelay(for failureCount: Int) -> TimeInterval {
    let capped = min(failureCount, 5)
    return min(pow(2.0, Double(capped)), 16.0)
  }
}
