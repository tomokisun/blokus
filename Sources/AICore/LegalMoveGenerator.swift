import Domain
import Foundation

public struct LegalMoveGenerator: Sendable {
  private struct PieceInfo: Sendable {
    var id: String
    var cellCount: Int
    var variants: [[BoardPoint]]
  }

  private struct ScoredMove {
    var action: CommandAction
    var score: Double
  }

  private static let orderedPieceInfos: [PieceInfo] = {
    PieceLibrary.pieces
      .map { piece in
        PieceInfo(
          id: piece.id,
          cellCount: piece.baseCells.count,
          variants: piece.variants
        )
      }
      .sorted { lhs, rhs in
        if lhs.cellCount == rhs.cellCount {
          return lhs.id < rhs.id
        }
        return lhs.cellCount > rhs.cellCount
      }
  }()

  public init() {}

  public func legalMoves(
    for state: GameState,
    playerId: PlayerID,
    maxCount: Int?
  ) -> [CommandAction] {
    guard state.phase == .playing || state.phase == .repair else { return [] }
    guard let remaining = state.remainingPieces[playerId], !remaining.isEmpty else {
      return [.pass]
    }

    let board = state.board
    let playerTag = playerId.compactIndex
    let firstMove = !board.rawCells.contains(playerTag)
    let center = Double(BoardConstants.maxBoardIndex) / 2.0
    var scoredMoves: [ScoredMove] = []
    scoredMoves.reserveCapacity(128)

    if firstMove {
      let startCorner = state.playerCorner(playerId)

      for info in Self.orderedPieceInfos {
        guard remaining.contains(info.id) else { continue }
        for variantId in info.variants.indices {
          let variant = info.variants[variantId]
          var triedOrigins = Set<Int>()

          for cell in variant {
            let ox = startCorner.x - cell.x
            let oy = startCorner.y - cell.y
            let originKey = oy * BoardConstants.boardSize + ox
            guard triedOrigins.insert(originKey).inserted else { continue }

            guard Self.canPlaceFirstMove(
              variant: variant, ox: ox, oy: oy, board: board
            ) else { continue }

            let distance = abs(Double(ox) - center) + abs(Double(oy) - center)
            let score = Double(info.cellCount) * 100 - distance
            scoredMoves.append(
              ScoredMove(
                action: .place(pieceId: info.id, variantId: variantId, origin: BoardPoint(x: ox, y: oy)),
                score: score
              )
            )
          }
        }
      }
    } else {
      // Build edge-adjacency and diagonal-anchor sets using flat indices for speed.
      let size = BoardConstants.boardSize
      let cellCount = BoardConstants.boardCellCount
      var edgeOfOwned = Array(repeating: false, count: cellCount)
      var anchorSet = Array(repeating: false, count: cellCount)
      var anchors: [BoardPoint] = []

      let raw = board.rawCells
      for idx in 0..<cellCount {
        guard raw[idx] == playerTag else { continue }
        let px = idx % size
        let py = idx / size

        if px > 0        { edgeOfOwned[idx - 1] = true }
        if px < size - 1 { edgeOfOwned[idx + 1] = true }
        if py > 0        { edgeOfOwned[idx - size] = true }
        if py < size - 1 { edgeOfOwned[idx + size] = true }
      }

      for idx in 0..<cellCount {
        guard raw[idx] == playerTag else { continue }
        let px = idx % size
        let py = idx / size

        let diags: [(Int, Int)] = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
        for (dx, dy) in diags {
          guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
          let di = dy * size + dx
          if raw[di] == 0, !edgeOfOwned[di], !anchorSet[di] {
            anchorSet[di] = true
            anchors.append(BoardPoint(x: dx, y: dy))
          }
        }
      }

      if anchors.isEmpty {
        return [.pass]
      }

      for info in Self.orderedPieceInfos {
        guard remaining.contains(info.id) else { continue }
        for variantId in info.variants.indices {
          let variant = info.variants[variantId]
          var triedOrigins = Set<Int>()

          for anchor in anchors {
            for cell in variant {
              let ox = anchor.x - cell.x
              let oy = anchor.y - cell.y
              let originKey = oy * BoardConstants.boardSize + ox
              guard triedOrigins.insert(originKey).inserted else { continue }

              guard Self.canPlaceNonFirst(
                variant: variant, ox: ox, oy: oy,
                board: board, edgeOfOwned: edgeOfOwned
              ) else { continue }

              let distance = abs(Double(ox) - center) + abs(Double(oy) - center)
              let score = Double(info.cellCount) * 100 - distance
              scoredMoves.append(
                ScoredMove(
                  action: .place(pieceId: info.id, variantId: variantId, origin: BoardPoint(x: ox, y: oy)),
                  score: score
                )
              )
            }
          }
        }
      }
    }

    if scoredMoves.isEmpty {
      return [.pass]
    }

    scoredMoves.sort { lhs, rhs in
      if lhs.score == rhs.score {
        return lhs.action.aiActionKey < rhs.action.aiActionKey
      }
      return lhs.score > rhs.score
    }

    if let maxCount, maxCount > 0, scoredMoves.count > maxCount {
      return Array(scoredMoves.prefix(maxCount).map(\.action))
    }
    return scoredMoves.map(\.action)
  }

  // MARK: - Inline placement checks (avoids PieceLibrary linear scan)

  private static func canPlaceFirstMove(
    variant: [BoardPoint], ox: Int, oy: Int, board: Board
  ) -> Bool {
    for cell in variant {
      let px = cell.x + ox
      let py = cell.y + oy
      guard px >= 0, px < BoardConstants.boardSize,
            py >= 0, py < BoardConstants.boardSize else { return false }
      if board.rawCells[py * BoardConstants.boardSize + px] != 0 { return false }
    }
    return true
  }

  private static func canPlaceNonFirst(
    variant: [BoardPoint], ox: Int, oy: Int,
    board: Board, edgeOfOwned: [Bool]
  ) -> Bool {
    let size = BoardConstants.boardSize
    for cell in variant {
      let px = cell.x + ox
      let py = cell.y + oy
      guard px >= 0, px < size, py >= 0, py < size else { return false }
      let idx = py * size + px
      if board.rawCells[idx] != 0 { return false }
      if edgeOfOwned[idx] { return false }
    }
    return true
  }
}
