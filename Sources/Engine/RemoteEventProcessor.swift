import Foundation
import Domain

public struct ForkEventRecord: Codable, Hashable, Sendable {
  public let eventId: UUID
  public let commandId: UUID
  public let coordinationSeq: Int
  public let reason: String
  public let observedAt: Date

  public init(eventId: UUID, commandId: UUID, coordinationSeq: Int, reason: String, observedAt: Date) {
    self.eventId = eventId
    self.commandId = commandId
    self.coordinationSeq = coordinationSeq
    self.reason = reason
    self.observedAt = observedAt
  }
}

public struct RemoteIngestResult: Sendable {
  public let acceptedEventIds: [UUID]
  public let committedEvents: [MoveEvent]
  public let queuedRanges: [ClosedRange<Int>]
  public let duplicateCommandIds: [UUID]
  public let orphanedEventIds: [UUID]
  public let forkedEvents: [ForkEventRecord]
  public let finalState: GameState
  public let phase: GamePhase

  public init(
    acceptedEventIds: [UUID],
    committedEvents: [MoveEvent],
    queuedRanges: [ClosedRange<Int>],
    duplicateCommandIds: [UUID],
    orphanedEventIds: [UUID],
    forkedEvents: [ForkEventRecord],
    finalState: GameState,
    phase: GamePhase
  ) {
    self.acceptedEventIds = acceptedEventIds
    self.committedEvents = committedEvents
    self.queuedRanges = queuedRanges
    self.duplicateCommandIds = duplicateCommandIds
    self.orphanedEventIds = orphanedEventIds
    self.forkedEvents = forkedEvents
    self.finalState = finalState
    self.phase = phase
  }
}

public enum RemoteEventProcessor {
  public static func process(
    incoming: [MoveEvent],
    state: GameState,
    existingEvents: [MoveEvent],
    chainHashComputer: (MoveEvent, String) -> String,
    now: Date
  ) -> RemoteIngestResult {
    var accepted: [UUID] = []
    var committed: [MoveEvent] = []
    var queued: [ClosedRange<Int>] = []
    var duplicate: [UUID] = []
    var orphan: [UUID] = []
    var forks: [ForkEventRecord] = []

    guard !incoming.isEmpty else {
      return RemoteIngestResult(
        acceptedEventIds: [],
        committedEvents: [],
        queuedRanges: [],
        duplicateCommandIds: [],
        orphanedEventIds: [],
        forkedEvents: [],
        finalState: state,
        phase: state.phase
      )
    }

    var working = state
    var events = existingEvents
    let sorted = incoming.sorted {
      if $0.coordinationSeq != $1.coordinationSeq {
        return $0.coordinationSeq < $1.coordinationSeq
      }
      return $0.createdAt < $1.createdAt
    }

    for remote in sorted {
      if let existed = events.first(where: { $0.commandId == remote.commandId }) {
        if existed.commandFingerprint == remote.commandFingerprint {
          duplicate.append(remote.commandId)
        } else {
          orphan.append(remote.eventId)
          forks.append(
            ForkEventRecord(
              eventId: remote.eventId,
              commandId: remote.commandId,
              coordinationSeq: remote.coordinationSeq,
              reason: "duplicate_commandId_diffFingerprint",
              observedAt: now
            )
          )
        }
        continue
      }

      let localForCoordination = events.first(where: { $0.coordinationSeq == remote.coordinationSeq })
      if let local = localForCoordination {
        if local.commandFingerprint != remote.commandFingerprint {
          orphan.append(remote.eventId)
          forks.append(
            ForkEventRecord(
              eventId: remote.eventId,
              commandId: remote.commandId,
              coordinationSeq: remote.coordinationSeq,
              reason: "coordination_conflict",
              observedAt: now
            )
          )
          continue
        }
        duplicate.append(remote.commandId)
        continue
      }

      if remote.coordinationSeq == working.coordinationSeq + 1 {
        var before = working
        if before.turnOrder.firstIndex(of: remote.playerId) == nil {
          orphan.append(remote.eventId)
          continue
        }
        let beforeFingerprint = before.stateFingerprint
        if before.apply(action: remote.payload, by: remote.playerId) == nil {
          var next = before
          let afterFingerprint = next.stateFingerprint
          let tempEvent = MoveEvent(
            eventId: remote.eventId,
            commandId: remote.commandId,
            commandFingerprint: remote.commandFingerprint,
            expectedSeq: remote.expectedSeq,
            coordinationSeq: remote.coordinationSeq,
            coordinationAuthorityId: remote.coordinationAuthorityId,
            source: remote.source,
            playerId: remote.playerId,
            payload: remote.payload,
            stateFingerprintBefore: beforeFingerprint,
            stateFingerprintAfter: afterFingerprint,
            status: .committed,
            chainHash: "",
            prevChainHash: before.stateHashChain.lastChainHash,
            createdAt: remote.createdAt
          )
          let computedChain = chainHashComputer(tempEvent, afterFingerprint)
          if !remote.chainHash.isEmpty && remote.chainHash != computedChain {
            orphan.append(remote.eventId)
            next.beginRepair(now)
          } else {
            next.stateHashChain.prevChainHash = before.stateHashChain.lastChainHash
            next.stateHashChain.lastChainHash = computedChain
            next.lastAppliedEventId = remote.eventId
            next.coordinationSeq = remote.coordinationSeq
            next.expectedSeq = max(next.expectedSeq, remote.expectedSeq + 1)
            next.snapshotSeq = max(next.snapshotSeq, remote.coordinationSeq)
            next.repairContext.retryCount = 0
            next.repairContext.consecutiveFailureCount = 0
            next.eventGaps.removeAll()
            next.phase = remote.source == .remote && next.phase == .repair ? .reconciling : next.phase
            let committedEvent = buildCommittedEventFromRemote(remote, beforeState: before, afterState: next, chainHash: computedChain)
            events.append(committedEvent)
            committed.append(committedEvent)
            accepted.append(remote.eventId)
            working = next
            continue
          }
          working = next
          continue
        }
        orphan.append(remote.eventId)
        working.beginRepair(now)
        continue
      }

      let gapRange = min(working.coordinationSeq + 1, remote.coordinationSeq)...max(working.coordinationSeq + 1, remote.coordinationSeq)
      GapManager.registerGap(from: gapRange.lowerBound, to: gapRange.upperBound, now: now, state: &working)
      queued.append(gapRange)
    }

    if working.phase == .reconciling || !working.eventGaps.isEmpty {
      working.phase = .reconciling
    } else if working.phase != .repair && working.phase != .readOnly && working.phase != .finished {
      working.phase = .playing
    }

    return RemoteIngestResult(
      acceptedEventIds: accepted,
      committedEvents: committed,
      queuedRanges: queued,
      duplicateCommandIds: duplicate,
      orphanedEventIds: orphan,
      forkedEvents: forks,
      finalState: working,
      phase: working.phase
    )
  }

  private static func buildCommittedEventFromRemote(
    _ remote: MoveEvent,
    beforeState: GameState,
    afterState: GameState,
    chainHash: String
  ) -> MoveEvent {
    MoveEvent(
      eventId: remote.eventId,
      commandId: remote.commandId,
      commandFingerprint: remote.commandFingerprint,
      expectedSeq: remote.expectedSeq,
      coordinationSeq: remote.coordinationSeq,
      coordinationAuthorityId: remote.coordinationAuthorityId,
      source: remote.source,
      playerId: remote.playerId,
      payload: remote.payload,
      stateFingerprintBefore: beforeState.stateFingerprint,
      stateFingerprintAfter: afterState.stateFingerprint,
      status: .committed,
      chainHash: chainHash,
      prevChainHash: beforeState.stateHashChain.lastChainHash,
      createdAt: remote.createdAt
    )
  }
}
