import Foundation

public struct PlayerID: RawRepresentable, Codable, Hashable, Sendable, CaseIterable,
                        ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public static let blue = PlayerID(rawValue: "Blue")
  public static let yellow = PlayerID(rawValue: "Yellow")
  public static let red = PlayerID(rawValue: "Red")
  public static let green = PlayerID(rawValue: "Green")

  public static var allCases: [PlayerID] { [.blue, .yellow, .red, .green] }
  public var displayName: String { rawValue }
  public var description: String { rawValue }
}
public typealias GameID = String

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

public struct BoardPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public var isInsideBoard: Bool {
    x >= 0 && x < 20 && y >= 0 && y < 20
  }

  public func translated(_ dx: Int, _ dy: Int) -> BoardPoint {
    BoardPoint(x: x + dx, y: y + dy)
  }
}

public enum CommandAction: Codable, Hashable, Sendable {
  case place(pieceId: String, variantId: Int, origin: BoardPoint)
  case pass
}

public struct GameCommand: Codable, Hashable, Sendable {
  public var commandId: UUID
  public var clientId: String
  public var expectedSeq: Int
  public var playerId: PlayerID
  public var action: CommandAction
  public var gameId: GameID
  public var schemaVersion: Int
  public var rulesVersion: Int
  public var pieceSetVersion: Int
  public var issuedAt: Date
  public var issuedNanos: Int64
  public var nonce: Int64
  public var authSig: String

  public init(
    commandId: UUID = UUID(),
    clientId: String,
    expectedSeq: Int,
    playerId: PlayerID,
    action: CommandAction,
    gameId: GameID,
    schemaVersion: Int,
    rulesVersion: Int,
    pieceSetVersion: Int,
    issuedAt: Date,
    issuedNanos: Int64,
    nonce: Int64,
    authSig: String
  ) {
    self.commandId = commandId
    self.clientId = clientId
    self.expectedSeq = expectedSeq
    self.playerId = playerId
    self.action = action
    self.gameId = gameId
    self.schemaVersion = schemaVersion
    self.rulesVersion = rulesVersion
    self.pieceSetVersion = pieceSetVersion
    self.issuedAt = issuedAt
    self.issuedNanos = issuedNanos
    self.nonce = nonce
    self.authSig = authSig
  }

  public var commandFingerprintV4: Data {
    commandFingerprintMaterial().sha256()
  }

  public func commandFingerprintMaterial() -> Data {
    var writer = CanonicalWriter()
    writer.appendUInt32(UInt32(gameId.utf8.count))
    writer.appendString(gameId)
    writer.appendUInt32(UInt32(schemaVersion))
    writer.appendUInt32(UInt32(rulesVersion))
    writer.appendUInt32(UInt32(pieceSetVersion))
    writer.appendUInt32(UInt32(playerId.rawValue.utf8.count))
    writer.appendString(playerId.rawValue)
    switch action {
    case let .place(pieceId: pieceId, variantId: variantId, origin: origin):
      writer.appendUInt8(1)
      writer.appendUInt32(UInt32(pieceId.utf8.count))
      writer.appendString(pieceId)
      writer.appendUInt32(UInt32(variantId))
      writer.appendInt32(Int32(origin.x))
      writer.appendInt32(Int32(origin.y))
    case .pass:
      writer.appendUInt8(2)
    }
    writer.appendUInt32(UInt32(expectedSeq))
    writer.appendString(commandId.uuidString)
    return writer.data
  }
}

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

public struct Player: Codable, Hashable, Sendable {
  public var id: PlayerID
  public var index: Int
  public var name: String
}

public struct Piece: Codable, Hashable, Sendable {
  public var id: String
  public var baseCells: [BoardPoint]

  public init(id: String, baseCells: [BoardPoint]) {
    self.id = id
    self.baseCells = baseCells
  }

  public var variants: [[BoardPoint]] {
    PieceVariantsCache.shared.variants(for: self)
  }
}

private final class PieceVariantsCache: @unchecked Sendable {
  static let shared = PieceVariantsCache()
  private var cache: [String: [[BoardPoint]]] = [:]

  func variants(for piece: Piece) -> [[BoardPoint]] {
    if let cached = cache[piece.id] { return cached }
    let canonicalBase = PieceVariantsCache.canonicalize(piece.baseCells)
    var generated: Set<String> = []
    var result: [[BoardPoint]] = []

    func add(_ cells: [BoardPoint]) {
      let normalized = PieceVariantsCache.canonicalize(cells)
      let key = normalized.map { "\($0.x),\($0.y)" }.joined(separator: "|")
      if !generated.contains(key) {
        generated.insert(key)
        result.append(normalized)
      }
    }

    var current = canonicalBase
    for _ in 0..<4 {
      add(current)
      add(current.map { BoardPoint(x: -$0.x, y: $0.y) })
      current = PieceVariantsCache.rotateClockwise(current)
    }
    cache[piece.id] = result
    return result
  }

  private static func rotateClockwise(_ points: [BoardPoint]) -> [BoardPoint] {
    let rotated = points.map { BoardPoint(x: $0.y, y: -$0.x) }
    return rotated
  }

  private static func canonicalize(_ points: [BoardPoint]) -> [BoardPoint] {
    guard let firstX = points.map(\.x).min(),
          let firstY = points.map(\.y).min() else {
      return []
    }
    return points
      .map { BoardPoint(x: $0.x - firstX, y: $0.y - firstY) }
      .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
  }
}

public enum PieceLibrary {
  public static let currentVersion = 5
  public static let pieces: [Piece] = [
    Piece(id: "mono-1", baseCells: [BoardPoint(x: 0, y: 0)]),
    Piece(id: "domino-2", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tri-3", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0)]),
    Piece(id: "tri-L-3", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tetri-I-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0)]),
    Piece(id: "tetri-L-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 0, y: 2), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tetri-O-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1)]),
    Piece(id: "tetri-T-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 1, y: 1)]),
    Piece(id: "tetri-Z-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1)]),
    Piece(id: "penta-I-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 4, y: 0)]),
    Piece(id: "penta-P-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 0, y: 2)]),
    Piece(id: "penta-F-5", baseCells: [BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 0)]),
    Piece(id: "penta-L-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 0, y: 1)]),
    Piece(id: "penta-T-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 1, y: 1)]),
    Piece(id: "penta-U-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1)]),
    Piece(id: "penta-V-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 0, y: 2), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0)]),
    Piece(id: "penta-W-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 2, y: 2)]),
    Piece(id: "penta-X-5", baseCells: [BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 1, y: 2)]),
    Piece(id: "penta-Y-5", baseCells: [BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 3, y: 1), BoardPoint(x: 1, y: 0)]),
    Piece(id: "penta-Z-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 2)]),
    Piece(id: "penta-N-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 2)])
  ]
}

public struct RecoveryResult: Sendable {
  public let restoredState: GameState
  public let orphanedEvents: [UUID]

  public init(restoredState: GameState, orphanedEvents: [UUID]) {
    self.restoredState = restoredState
    self.orphanedEvents = orphanedEvents
  }
}
