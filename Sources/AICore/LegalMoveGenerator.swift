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

    let center = Double(BoardConstants.maxBoardIndex) / 2.0
    var scoredMoves: [ScoredMove] = []
    scoredMoves.reserveCapacity(128)

    for info in Self.orderedPieceInfos {
      guard remaining.contains(info.id) else { continue }
      for variantId in info.variants.indices {
        for y in 0..<BoardConstants.boardSize {
          for x in 0..<BoardConstants.boardSize {
            let origin = BoardPoint(x: x, y: y)
            guard state.canPlace(
              pieceId: info.id,
              variantId: variantId,
              origin: origin,
              playerId: playerId
            ) else {
              continue
            }

            let distance = abs(Double(x) - center) + abs(Double(y) - center)
            let score = Double(info.cellCount) * 100 - distance
            scoredMoves.append(
              ScoredMove(
                action: .place(pieceId: info.id, variantId: variantId, origin: origin),
                score: score
              )
            )
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
}
