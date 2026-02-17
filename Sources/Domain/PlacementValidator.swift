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

    for pieceId in remaining {
      guard let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else { continue }
      for variantIndex in piece.variants.indices {
        for y in 0..<BoardConstants.boardSize {
          for x in 0..<BoardConstants.boardSize {
            if canPlace(pieceId: pieceId, variantId: variantIndex, origin: BoardPoint(x: x, y: y), playerId: playerId, state: state) {
              return true
            }
          }
        }
      }
    }
    return false
  }

  private static func boardPointSafe(_ point: BoardPoint) -> BoardPoint? {
    guard point.isInsideBoard else { return nil }
    return point
  }
}
