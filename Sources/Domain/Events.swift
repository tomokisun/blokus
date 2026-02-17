import Foundation

public enum MoveEventStatus: String, Codable, Sendable {
  case proposed
  case queued
  case committed
  case rejected
  case orphan
}

public enum MoveEventSource: String, Codable, Sendable {
  case local
  case remote
}

public struct MoveEvent: Codable, Hashable, Sendable {
  public let eventId: UUID
  public let commandId: UUID
  public let commandFingerprint: Data
  public let expectedSeq: Int
  public let coordinationSeq: Int
  public let coordinationAuthorityId: PlayerID
  public let source: MoveEventSource
  public let playerId: PlayerID
  public let payload: CommandAction
  public let stateFingerprintBefore: String
  public let stateFingerprintAfter: String
  public let status: MoveEventStatus
  public let chainHash: String
  public let prevChainHash: String
  public let createdAt: Date

  public init(
    eventId: UUID,
    commandId: UUID,
    commandFingerprint: Data,
    expectedSeq: Int,
    coordinationSeq: Int,
    coordinationAuthorityId: PlayerID,
    source: MoveEventSource,
    playerId: PlayerID,
    payload: CommandAction,
    stateFingerprintBefore: String,
    stateFingerprintAfter: String,
    status: MoveEventStatus,
    chainHash: String,
    prevChainHash: String,
    createdAt: Date
  ) {
    self.eventId = eventId
    self.commandId = commandId
    self.commandFingerprint = commandFingerprint
    self.expectedSeq = expectedSeq
    self.coordinationSeq = coordinationSeq
    self.coordinationAuthorityId = coordinationAuthorityId
    self.source = source
    self.playerId = playerId
    self.payload = payload
    self.stateFingerprintBefore = stateFingerprintBefore
    self.stateFingerprintAfter = stateFingerprintAfter
    self.status = status
    self.chainHash = chainHash
    self.prevChainHash = prevChainHash
    self.createdAt = createdAt
  }

  public func expectedChainHash() -> String {
    var writer = CanonicalWriter()
    writer.appendString(prevChainHash)
    writer.appendString(stateFingerprintBefore)
    writer.appendString(stateFingerprintAfter)
    writer.appendData(commandFingerprint)
    writer.appendUInt32(UInt32(coordinationSeq))
    writer.appendUInt32(UInt32(expectedSeq))
    writer.appendString(coordinationAuthorityId.rawValue)
    writer.appendString(playerId.rawValue)
    return writer.data.sha256().hexString
  }
}
