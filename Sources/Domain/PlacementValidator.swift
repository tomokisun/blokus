import Foundation

public enum PlacementValidator {
  public static func canPlace(
    pieceId: String,
    variantId: Int,
    origin: BoardPoint,
    playerId: PlayerID,
    state: GameState
  ) -> Bool {
    guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { return false }
    let available = state.remainingPieces[playerId, default: []]
    guard available.contains(pieceId) else { return false }
    let variants = piece.variants
    guard variantId >= 0, variantId < variants.count else { return false }
    let variant = variants[variantId]

    var absoluteCells: [BoardPoint] = []
    for variantCell in variant {
      let point = BoardPoint(x: variantCell.x + origin.x, y: variantCell.y + origin.y)
      if !point.isInsideBoard { return false }
      if state.board[point] != nil { return false }
      absoluteCells.append(point)
    }

    for cell in absoluteCells {
      let touchesOwnSide = [
        cell.translated(-1, 0),
        cell.translated(1, 0),
        cell.translated(0, -1),
        cell.translated(0, 1)
      ].compactMap { n in boardPointSafe(n).flatMap { state.board[$0] } }
        .contains(where: { $0 == playerId })
      if touchesOwnSide { return false }
    }

    let firstMove = !state.hasPlacedPiece(for: playerId)
    if firstMove {
      return absoluteCells.contains(state.playerCorner(playerId))
    }

    let touchesOwnCorner = absoluteCells.contains { cell in
      return [cell.translated(-1, -1), cell.translated(1, -1), cell.translated(-1, 1), cell.translated(1, 1)]
        .compactMap(boardPointSafe)
        .contains(where: { state.board[$0] == playerId })
    }
    return touchesOwnCorner
  }

  public static func hasAnyLegalMove(for playerId: PlayerID, state: GameState) -> Bool {
    guard let remaining = state.remainingPieces[playerId], !remaining.isEmpty else { return false }

    let board = state.board
    let firstMove = !state.hasPlacedPiece(for: playerId)

    if firstMove {
      let startCorner = state.playerCorner(playerId)
      for pieceId in remaining {
        guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { continue }
        for variant in piece.variants {
          for cell in variant {
            let ox = startCorner.x - cell.x
            let oy = startCorner.y - cell.y
            if checkAllCellsOnBoardAndEmpty(variant: variant, ox: ox, oy: oy, board: board) {
              return true
            }
          }
        }
      }
      return false
    }

    // Build edge-adjacency and anchor sets.
    let size = BoardConstants.boardSize
    let cellCount = BoardConstants.boardCellCount
    var edgeOfOwned = Array(repeating: false, count: cellCount)
    var anchors: [BoardPoint] = []
    var anchorSeen = Array(repeating: false, count: cellCount)

    for idx in 0..<cellCount {
      guard board.cells[idx] == playerId else { continue }
      let px = idx % size
      let py = idx / size
      if px > 0        { edgeOfOwned[idx - 1] = true }
      if px < size - 1 { edgeOfOwned[idx + 1] = true }
      if py > 0        { edgeOfOwned[idx - size] = true }
      if py < size - 1 { edgeOfOwned[idx + size] = true }
    }

    for idx in 0..<cellCount {
      guard board.cells[idx] == playerId else { continue }
      let px = idx % size
      let py = idx / size
      let diags = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
      for (dx, dy) in diags {
        guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
        let di = dy * size + dx
        if board.cells[di] == nil, !edgeOfOwned[di], !anchorSeen[di] {
          anchorSeen[di] = true
          anchors.append(BoardPoint(x: dx, y: dy))
        }
      }
    }

    if anchors.isEmpty { return false }

    for pieceId in remaining {
      guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { continue }
      for variant in piece.variants {
        var triedOrigins = Set<Int>()
        for anchor in anchors {
          for cell in variant {
            let ox = anchor.x - cell.x
            let oy = anchor.y - cell.y
            let originKey = oy * size + ox
            guard triedOrigins.insert(originKey).inserted else { continue }
            if checkPlacementNonFirst(variant: variant, ox: ox, oy: oy, board: board, edgeOfOwned: edgeOfOwned, size: size) {
              return true
            }
          }
        }
      }
    }
    return false
  }

  private static func checkAllCellsOnBoardAndEmpty(
    variant: [BoardPoint], ox: Int, oy: Int, board: Board
  ) -> Bool {
    let size = BoardConstants.boardSize
    for cell in variant {
      let px = cell.x + ox
      let py = cell.y + oy
      guard px >= 0, px < size, py >= 0, py < size else { return false }
      if board.cells[py * size + px] != nil { return false }
    }
    return true
  }

  private static func checkPlacementNonFirst(
    variant: [BoardPoint], ox: Int, oy: Int,
    board: Board, edgeOfOwned: [Bool], size: Int
  ) -> Bool {
    for cell in variant {
      let px = cell.x + ox
      let py = cell.y + oy
      guard px >= 0, px < size, py >= 0, py < size else { return false }
      let idx = py * size + px
      if board.cells[idx] != nil { return false }
      if edgeOfOwned[idx] { return false }
    }
    return true
  }

  private static func boardPointSafe(_ point: BoardPoint) -> BoardPoint? {
    guard point.isInsideBoard else { return nil }
    return point
  }
}
