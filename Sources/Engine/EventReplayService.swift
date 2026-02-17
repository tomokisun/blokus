import Foundation
import Domain

public enum EventReplayService {
  public static func replay(
    events sourceEvents: [MoveEvent],
    from initialState: GameState,
    chainHashComputer: (_ event: MoveEvent, _ afterFingerprint: String) -> String
  ) -> RecoveryResult {
    var restored = initialState
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
        source: event,
        chainHashComputer: chainHashComputer
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

  static func applyDuringReplay(
    action: CommandAction,
    playerId: PlayerID,
    expectedBefore: GameState,
    source: MoveEvent,
    chainHashComputer: (_ event: MoveEvent, _ afterFingerprint: String) -> String
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
    let chainHash = chainHashComputer(writerEvent, afterFingerprint)
    return (next, afterFingerprint, chainHash)
  }

  static func validateReplayPrecondition(
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
}
