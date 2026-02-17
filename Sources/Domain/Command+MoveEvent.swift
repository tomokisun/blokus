import Foundation

public extension GameCommand {
  func toMoveEvent(
    status: MoveEventStatus,
    stateBefore: GameState,
    stateAfter: GameState,
    prevChainHash: String,
    chainHash: String
  ) -> MoveEvent {
    MoveEvent(
      eventId: UUID(),
      commandId: commandId,
      commandFingerprint: commandFingerprintV4,
      expectedSeq: expectedSeq,
      coordinationSeq: stateAfter.coordinationSeq,
      coordinationAuthorityId: stateAfter.authority.coordinationAuthorityId,
      source: .local,
      playerId: playerId,
      payload: action,
      stateFingerprintBefore: stateBefore.stateFingerprint,
      stateFingerprintAfter: stateAfter.stateFingerprint,
      status: status,
      chainHash: chainHash,
      prevChainHash: prevChainHash,
      createdAt: stateAfter.createdAt
    )
  }
}
