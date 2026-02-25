import Domain
import Foundation

public enum BoardTransform: Int, CaseIterable, Sendable {
  case identity = 0
  case rotate90 = 1
  case rotate180 = 2
  case rotate270 = 3
  case flipH = 4
  case flipH_rotate90 = 5
  case flipH_rotate180 = 6
  case flipH_rotate270 = 7

  public static let augmentations: [BoardTransform] = [
    .rotate90, .rotate180, .rotate270,
    .flipH, .flipH_rotate90, .flipH_rotate180, .flipH_rotate270,
  ]

  public func apply(_ p: BoardPoint, boardSize: Int = BoardConstants.boardSize) -> BoardPoint {
    let s = boardSize - 1
    switch self {
    case .identity: return p
    case .rotate90: return BoardPoint(x: s - p.y, y: p.x)
    case .rotate180: return BoardPoint(x: s - p.x, y: s - p.y)
    case .rotate270: return BoardPoint(x: p.y, y: s - p.x)
    case .flipH: return BoardPoint(x: s - p.x, y: p.y)
    case .flipH_rotate90: return BoardPoint(x: s - p.y, y: s - p.x)
    case .flipH_rotate180: return BoardPoint(x: p.x, y: s - p.y)
    case .flipH_rotate270: return BoardPoint(x: p.y, y: p.x)
    }
  }

  public func applyRelative(_ p: BoardPoint) -> BoardPoint {
    switch self {
    case .identity: return p
    case .rotate90: return BoardPoint(x: -p.y, y: p.x)
    case .rotate180: return BoardPoint(x: -p.x, y: -p.y)
    case .rotate270: return BoardPoint(x: p.y, y: -p.x)
    case .flipH: return BoardPoint(x: -p.x, y: p.y)
    case .flipH_rotate90: return BoardPoint(x: -p.y, y: -p.x)
    case .flipH_rotate180: return BoardPoint(x: p.x, y: -p.y)
    case .flipH_rotate270: return BoardPoint(x: p.y, y: p.x)
    }
  }
}

public enum DataAugmentation {
  private static let variantLookup: [String: [[Int]]] = {
    var table: [String: [[Int]]] = [:]
    for piece in PieceLibrary.pieces {
      var pieceTable: [[Int]] = []
      for (vid, variant) in piece.variants.enumerated() {
        var transformMap: [Int] = []
        for t in BoardTransform.allCases {
          let transformed = variant.map { t.applyRelative($0) }
          let minX = transformed.map(\.x).min() ?? 0
          let minY = transformed.map(\.y).min() ?? 0
          let normalized = Set(transformed.map { BoardPoint(x: $0.x - minX, y: $0.y - minY) })
          let matchVid = piece.variants.firstIndex { Set($0) == normalized } ?? vid
          transformMap.append(matchVid)
        }
        pieceTable.append(transformMap)
      }
      table[piece.id] = pieceTable
    }
    return table
  }()

  public static func transformBoard(
    _ encoding: [UInt8],
    transform: BoardTransform,
    size: Int = BoardConstants.boardSize
  ) -> [UInt8] {
    var result = Array(repeating: UInt8(0), count: encoding.count)
    for y in 0..<size {
      for x in 0..<size {
        let srcIdx = y * size + x
        let tp = transform.apply(BoardPoint(x: x, y: y), boardSize: size)
        let dstIdx = tp.y * size + tp.x
        result[dstIdx] = encoding[srcIdx]
      }
    }
    return result
  }

  public static func transformAction(
    _ action: CommandAction,
    transform: BoardTransform
  ) -> CommandAction {
    guard transform != .identity else { return action }
    switch action {
    case .pass: return .pass
    case let .place(pieceId, variantId, origin):
      guard let piece = PieceLibrary.pieceById[pieceId],
        let variant = piece.variants[safe: variantId]
      else { return action }

      let absoluteCells = variant.map {
        BoardPoint(x: origin.x + $0.x, y: origin.y + $0.y)
      }
      let transformed = absoluteCells.map { transform.apply($0) }
      let minX = transformed.map(\.x).min()!
      let minY = transformed.map(\.y).min()!
      let newOrigin = BoardPoint(x: minX, y: minY)

      let newVid = variantLookup[pieceId]?[variantId][transform.rawValue] ?? variantId

      return .place(pieceId: pieceId, variantId: newVid, origin: newOrigin)
    }
  }

  public static func augmentPosition(
    _ position: TrainingPosition,
    transform: BoardTransform
  ) -> TrainingPosition {
    guard transform != .identity else { return position }

    let newBoard = transformBoard(position.boardEncoding, transform: transform)
    let newSelectedAction = transformAction(position.selectedAction, transform: transform)
    let newPolicy = position.policy.map { entry in
      let newAction = transformAction(entry.action, transform: transform)
      return MovePolicyEntry(action: newAction, probability: entry.probability)
    }

    return TrainingPosition(
      gameId: position.gameId + "-t\(transform.rawValue)",
      ply: position.ply,
      activePlayer: position.activePlayer,
      boardEncoding: newBoard,
      selectedAction: newSelectedAction,
      policy: newPolicy,
      outcomeByPlayer: position.outcomeByPlayer
    )
  }

  public static func augmentPositions(
    _ positions: [TrainingPosition]
  ) -> [TrainingPosition] {
    var result = positions
    result.reserveCapacity(positions.count * 8)
    for position in positions {
      for transform in BoardTransform.augmentations {
        result.append(augmentPosition(position, transform: transform))
      }
    }
    return result
  }
}
