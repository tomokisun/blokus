import Foundation

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
