import Foundation

public struct GameState: Codable, Hashable, Sendable {
  public static let schemaVersion = 5
  public static let rulesVersion = 1
  public static let hashSpecVersion = 1
  public static let scoringVersion = 1

  public let gameId: GameID
  public let schemaVersion: Int
  public let createdAt: Date
  public var phase: GamePhase
  public var authority: CoordinationAuthority
  public var localAuthorityMode: Bool
  public var players: [Player]
  public var turnOrder: [PlayerID]
  public var activeIndex: Int
  public var board: [PlayerID?]
  public var remainingPieces: [PlayerID: Set<String>]
  public var consecutivePasses: Int
  public var expectedSeq: Int
  public var coordinationSeq: Int
  public var stateFingerprint: String
  public var snapshotSeq: Int
  public var lastAppliedEventId: UUID?
  public var stateHashChain: StateHashChain
  public var repairContext: RepairContext
  public var eventGaps: [EventGap]

  public init(
    gameId: GameID,
    players: [PlayerID],
    authorityId: PlayerID,
    now: Date = .init(),
    localAuthorityMode: Bool = true
  ) {
    self.gameId = gameId
    self.schemaVersion = GameState.schemaVersion
    self.createdAt = now
    self.phase = players.count < 2 ? .waiting : .playing
    self.authority = CoordinationAuthority(
      coordinationAuthorityId: authorityId,
      coordinationEpoch: 1,
      effectiveAt: now
    )
    self.localAuthorityMode = localAuthorityMode
    self.turnOrder = players
    self.activeIndex = 0
    self.players = players.enumerated().map { index, playerId in
      Player(id: playerId, index: index, name: playerId.rawValue)
    }
    self.board = Array(repeating: nil, count: 400)
    let allPieceIds = Set(PieceLibrary.pieces.map(\.id))
    self.remainingPieces = Dictionary(uniqueKeysWithValues: players.map { ($0, allPieceIds) })
    self.consecutivePasses = 0
    self.expectedSeq = 0
    self.coordinationSeq = 0
    self.snapshotSeq = 0
    self.lastAppliedEventId = nil
    self.stateFingerprint = ""
    self.stateHashChain = StateHashChain(prevChainHash: "", lastChainHash: "")
    self.repairContext = RepairContext(retryCount: 0, firstFailureAt: nil, lastFailureAt: nil, consecutiveFailureCount: 0)
    self.eventGaps = []
    self.stateFingerprint = computeStateFingerprint()
  }

  public var activePlayerId: PlayerID {
    turnOrder[activeIndex]
  }

  private func index(_ point: BoardPoint) -> Int {
    point.y * 20 + point.x
  }

  public func boardPoint(for index: Int) -> BoardPoint {
    BoardPoint(x: index % 20, y: index / 20)
  }

  public func playerCorner(_ playerId: PlayerID) -> BoardPoint {
    let cornersByPlayers: [BoardPoint] = [
      BoardPoint(x: 0, y: 0),
      BoardPoint(x: 19, y: 19),
      BoardPoint(x: 19, y: 0),
      BoardPoint(x: 0, y: 19)
    ]
    guard let idx = turnOrder.firstIndex(of: playerId) else { return BoardPoint(x: 0, y: 0) }
    return cornersByPlayers[idx % 4]
  }

  public func hasPlacedPiece(for playerId: PlayerID) -> Bool {
    return board.contains(where: { $0 == playerId })
  }

  public func canPlace(pieceId: String, variantId: Int, origin: BoardPoint, playerId: PlayerID) -> Bool {
    guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { return false }
    let available = remainingPieces[playerId, default: []]
    guard available.contains(pieceId) else { return false }
    let variants = piece.variants
    guard variantId >= 0, variantId < variants.count else { return false }
    let variant = variants[variantId]

    var absoluteCells: [BoardPoint] = []
    for variantCell in variant {
      let point = BoardPoint(x: variantCell.x + origin.x, y: variantCell.y + origin.y)
      if !point.isInsideBoard { return false }
      if board[index(point)] != nil { return false }
      absoluteCells.append(point)
    }

    for cell in absoluteCells {
      let touchesOwnSide = [
        cell.translated(-1, 0),
        cell.translated(1, 0),
        cell.translated(0, -1),
        cell.translated(0, 1)
      ].compactMap { n in boardPointSafe(n).flatMap { board[index($0)] } }
        .contains(where: { $0 == playerId })
      if touchesOwnSide { return false }
    }

    let firstMove = !hasPlacedPiece(for: playerId)
    if firstMove {
      return absoluteCells.contains(playerCorner(playerId))
    }

    let touchesOwnCorner = absoluteCells.contains { cell in
      return [cell.translated(-1, -1), cell.translated(1, -1), cell.translated(-1, 1), cell.translated(1, 1)]
        .compactMap(boardPointSafe)
        .contains(where: { board[index($0)] == playerId })
    }
    return touchesOwnCorner
  }

  public func hasAnyLegalMove(for playerId: PlayerID) -> Bool {
    guard let remaining = remainingPieces[playerId], !remaining.isEmpty else { return false }

    for pieceId in remaining {
      guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { continue }
      for variantIndex in piece.variants.indices {
        for y in 0..<20 {
          for x in 0..<20 {
            if canPlace(pieceId: pieceId, variantId: variantIndex, origin: BoardPoint(x: x, y: y), playerId: playerId) {
              return true
            }
          }
        }
      }
    }
    return false
  }

  public mutating func apply(action: CommandAction, by playerId: PlayerID) -> SubmitRejectReason? {
    switch action {
    case .pass:
      guard !hasAnyLegalMove(for: playerId) else { return .illegalPass }
      consecutivePasses += 1

    case let .place(pieceId: pieceId, variantId: variantId, origin: origin):
      guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { return .invalidPlacement }
      let remaining = remainingPieces[playerId, default: []]
      guard remaining.contains(pieceId) else { return .invalidPlacement }
      guard canPlace(pieceId: pieceId, variantId: variantId, origin: origin, playerId: playerId) else { return .invalidPlacement }
      guard let pieceVariant = piece.variants[safe: variantId] else { return .invalidPlacement }
      for point in pieceVariant {
        let boardPoint = BoardPoint(x: point.x + origin.x, y: point.y + origin.y)
        board[index(boardPoint)] = playerId
      }
      remainingPieces[playerId] = remaining.subtracting([pieceId])
      consecutivePasses = 0
    }

    activeIndex = (activeIndex + 1) % max(1, turnOrder.count)
    if consecutivePasses >= turnOrder.count {
      phase = .finished
    }
    expectedSeq += 1
    coordinationSeq += 1
    stateFingerprint = computeStateFingerprint()
    return nil
  }

  public mutating func beginRepair(_ now: Date) {
    phase = .repair
    if repairContext.firstFailureAt == nil {
      repairContext.firstFailureAt = now
    }
    repairContext.lastFailureAt = now
    repairContext.consecutiveFailureCount += 1
    repairContext.retryCount += 1
  }

  public mutating func beginReadOnly(_ now: Date) {
    phase = .readOnly
    if repairContext.firstFailureAt == nil {
      repairContext.firstFailureAt = now
    }
    repairContext.lastFailureAt = now
    repairContext.consecutiveFailureCount += 1
  }

  public func computeStateFingerprint() -> String {
    var writer = CanonicalWriter()
    for idx in board.indices {
      let marker = board[idx].flatMap { turnOrder.firstIndex(of: $0).map { $0 + 1 } } ?? 0
      writer.appendUInt8(UInt8(marker))
    }
    writer.appendUInt32(UInt32(activeIndex))
    writer.appendUInt32(UInt32(consecutivePasses))
    writer.appendUInt32(UInt32(expectedSeq))
    writer.appendUInt32(UInt32(coordinationSeq))
    writer.appendUInt32(UInt32(turnOrder.count))
    for pieceOwner in turnOrder {
      writer.appendUInt32(UInt32(remainingPieces[pieceOwner, default: []].count))
    }
    return writer.data.sha256().hexString
  }

  private func boardPointSafe(_ point: BoardPoint) -> BoardPoint? {
    guard point.isInsideBoard else { return nil }
    return point
  }

  public static func initial(
    gameId: GameID,
    players: [PlayerID],
    authorityId: PlayerID
  ) -> GameState {
    GameState(gameId: gameId, players: players, authorityId: authorityId)
  }
}
