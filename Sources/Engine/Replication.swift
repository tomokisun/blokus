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
  public let queuedRanges: [ClosedRange<Int>]
  public let duplicateCommandIds: [UUID]
  public let orphanedEventIds: [UUID]
  public let forkedEvents: [ForkEventRecord]
  public let finalState: GameState
  public let phase: GamePhase

  public init(
    acceptedEventIds: [UUID],
    queuedRanges: [ClosedRange<Int>],
    duplicateCommandIds: [UUID],
    orphanedEventIds: [UUID],
    forkedEvents: [ForkEventRecord],
    finalState: GameState,
    phase: GamePhase
  ) {
    self.acceptedEventIds = acceptedEventIds
    self.queuedRanges = queuedRanges
    self.duplicateCommandIds = duplicateCommandIds
    self.orphanedEventIds = orphanedEventIds
    self.forkedEvents = forkedEvents
    self.finalState = finalState
    self.phase = phase
  }
}

public extension GameEngine {
  func makeGap(from: Int, to: Int, now: Date) -> EventGap {
    let effectiveFrom = max(0, min(from, to))
    let effectiveTo = max(effectiveFrom, max(0, to))
    return EventGap(
      fromSeq: effectiveFrom,
      toSeq: effectiveTo,
      detectedAt: now,
      retryCount: 0,
      nextRetryAt: now.addingTimeInterval(1),
      lastError: "coordination_gap",
      maxRetries: 5,
      deadlineAt: now.addingTimeInterval(31)
    )
  }

  func markExistingGapOrCreate(_ range: ClosedRange<Int>, state: inout GameState, now: Date) {
    let exists = state.eventGaps.contains { gap in
      gap.fromSeq <= range.lowerBound && gap.toSeq >= range.upperBound
    }
    guard !exists else {
      if state.phase != .repair && state.phase != .readOnly { state.beginRepair(now) }
      return
    }
    state.eventGaps.append(makeGap(from: range.lowerBound, to: range.upperBound, now: now))
    state.beginRepair(now)
  }

  func buildCommittedEventFromRemote(
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

  func applyRemoteEvents(_ incoming: [MoveEvent], at now: Date = .init()) -> RemoteIngestResult {
    var accepted: [UUID] = []
    var queued: [ClosedRange<Int>] = []
    var duplicate: [UUID] = []
    var orphan: [UUID] = []
    var forks: [ForkEventRecord] = []

    guard !incoming.isEmpty else {
      return RemoteIngestResult(
        acceptedEventIds: [],
        queuedRanges: [],
        duplicateCommandIds: [],
        orphanedEventIds: [],
        forkedEvents: [],
        finalState: state,
        phase: state.phase
      )
    }

    var working = state
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
          let computedChain = computeChainHash(tempEvent, afterFingerprint: afterFingerprint)
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
            let committed = buildCommittedEventFromRemote(remote, beforeState: before, afterState: next, chainHash: computedChain)
            events.append(committed)
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
      markExistingGapOrCreate(gapRange, state: &working, now: now)
      queued.append(gapRange)
    }

    if working.phase == .reconciling || !working.eventGaps.isEmpty {
      working.phase = .reconciling
    } else if working.phase != .repair && working.phase != .readOnly && working.phase != .finished {
      working.phase = .playing
    }
    state = working
    return RemoteIngestResult(
      acceptedEventIds: accepted,
      queuedRanges: queued,
      duplicateCommandIds: duplicate,
      orphanedEventIds: orphan,
      forkedEvents: forks,
      finalState: state,
      phase: state.phase
    )
  }
}
