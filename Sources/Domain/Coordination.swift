import Foundation

public struct CoordinationAuthority: Codable, Hashable, Sendable {
  public var coordinationAuthorityId: PlayerID
  public var coordinationEpoch: Int
  public var effectiveAt: Date
}

public struct RepairContext: Codable, Hashable, Sendable {
  public var retryCount: Int
  public var firstFailureAt: Date?
  public var lastFailureAt: Date?
  public var consecutiveFailureCount: Int
}

public struct EventGap: Codable, Hashable, Sendable {
  public var fromSeq: Int
  public var toSeq: Int
  public var detectedAt: Date
  public var retryCount: Int
  public var nextRetryAt: Date
  public var lastError: String?
  public var maxRetries: Int
  public var deadlineAt: Date

  public init(
    fromSeq: Int,
    toSeq: Int,
    detectedAt: Date,
    retryCount: Int,
    nextRetryAt: Date,
    lastError: String?,
    maxRetries: Int,
    deadlineAt: Date
  ) {
    self.fromSeq = fromSeq
    self.toSeq = toSeq
    self.detectedAt = detectedAt
    self.retryCount = retryCount
    self.nextRetryAt = nextRetryAt
    self.lastError = lastError
    self.maxRetries = maxRetries
    self.deadlineAt = deadlineAt
  }
}

public struct StateHashChain: Codable, Hashable, Sendable {
  public var prevChainHash: String
  public var lastChainHash: String

  public init(prevChainHash: String, lastChainHash: String) {
    self.prevChainHash = prevChainHash
    self.lastChainHash = lastChainHash
  }
}

public struct RecoveryResult: Sendable {
  public let restoredState: GameState
  public let orphanedEvents: [UUID]

  public init(restoredState: GameState, orphanedEvents: [UUID]) {
    self.restoredState = restoredState
    self.orphanedEvents = orphanedEvents
  }
}
