import Foundation
import Domain

public enum StoreError: Error {
  case openFailed(String)
  case prepareFailed(String)
  case bindFailed(String)
  case executionFailed(String)
  case decodeFailed(String)
  case migrationFailed(from: Int, to: Int, reason: String)
}

public struct SQLiteAuditLog: Codable, Hashable, Sendable {
  public let id: UUID
  public let gameId: String
  public let level: String
  public let category: String
  public let message: String
  public let details: String?
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    gameId: String,
    level: String,
    category: String,
    message: String,
    details: String?,
    createdAt: Date = .init()
  ) {
    self.id = id
    self.gameId = gameId
    self.level = level
    self.category = category
    self.message = message
    self.details = details
    self.createdAt = createdAt
  }
}

public struct OperationalMetrics: Sendable {
  public let gapOpenCount: Int64
  public let gapRecoveryDurationMs: Int64
  public let queuedCount: Int64
  public let forkCount: Int64
  public let orphanRate: Double
  public let latestRetryCount: Int64

  public init(
    gapOpenCount: Int64,
    gapRecoveryDurationMs: Int64,
    queuedCount: Int64,
    forkCount: Int64,
    orphanRate: Double,
    latestRetryCount: Int64
  ) {
    self.gapOpenCount = gapOpenCount
    self.gapRecoveryDurationMs = gapRecoveryDurationMs
    self.queuedCount = queuedCount
    self.forkCount = forkCount
    self.orphanRate = orphanRate
    self.latestRetryCount = latestRetryCount
  }
}

public struct RecoveryPlan: Sendable {
  public let restoredState: GameState
  public let orphanedEventIds: [UUID]

  public init(restoredState: GameState, orphanedEventIds: [UUID]) {
    self.restoredState = restoredState
    self.orphanedEventIds = orphanedEventIds
  }
}

public struct ReadOnlyContext: Sendable {
  public let gameId: GameID
  public let phase: GamePhase
  public let openGaps: [EventGap]
  public let latestMatchedCoordinationSeq: Int
  public let lastSeenOrphanEventId: UUID?
  public let lastSeenOrphanReason: String?
  public let retryCount: Int
  public let lastFailureAt: Date?

  public init(
    gameId: GameID,
    phase: GamePhase,
    openGaps: [EventGap],
    latestMatchedCoordinationSeq: Int,
    lastSeenOrphanEventId: UUID?,
    lastSeenOrphanReason: String?,
    retryCount: Int,
    lastFailureAt: Date?
  ) {
    self.gameId = gameId
    self.phase = phase
    self.openGaps = openGaps
    self.latestMatchedCoordinationSeq = latestMatchedCoordinationSeq
    self.lastSeenOrphanEventId = lastSeenOrphanEventId
    self.lastSeenOrphanReason = lastSeenOrphanReason
    self.retryCount = retryCount
    self.lastFailureAt = lastFailureAt
  }
}
