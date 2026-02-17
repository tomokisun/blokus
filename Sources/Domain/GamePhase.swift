import Foundation

public enum GamePhase: String, Codable, Sendable, CaseIterable {
  case waiting
  case syncing
  case reconciling
  case repair
  case readOnly
  case playing
  case finished
}

public enum SubmitRejectReason: String, Codable, Sendable {
  case invalidSignature
  case replayOrDuplicate
  case invalidAuthority
  case invalidTurn
  case invalidPlacement
  case illegalPass
  case rateLimit
  case schemaMismatch
  case versionMismatch
}

public enum GameSubmitStatus: Equatable {
  case accepted(GameState)
  case queued(GameState, ClosedRange<Int>)
  case duplicate(GameState, UUID)
  case rejected(GameState, SubmitRejectReason, retryable: Bool)
  case authorityMismatch(GameState)
}
