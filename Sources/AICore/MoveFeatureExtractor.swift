import Domain
import Foundation

public struct BoardContext: Sendable {
  public let size: Int
  public let rawCells: [UInt8]
  public let playerTag: UInt8
  public let isFirstMove: Bool
  public let progress: Double
  public let playerLead: Double
  public let activeCellCount: Int
  public let edgeOfOwned: [Bool]
  public let ownAnchors: [Bool]
  public let opponentAnchorUnion: [Bool]

  public init(rawCells: [UInt8], playerTag: UInt8, playerCount: Int = 4) {
    let size = BoardConstants.boardSize
    let cellCount = size * size
    self.size = size
    self.rawCells = rawCells
    self.playerTag = playerTag

    var edgeOfOwned = Array(repeating: false, count: cellCount)
    var ownAnchors = Array(repeating: false, count: cellCount)
    var opponentAnchorUnion = Array(repeating: false, count: cellCount)
    var activeCells = 0
    var totalFilled = 0

    // Opponent edge maps (temporary, needed to compute opponent anchors)
    var opponentEdge = Array(repeating: false, count: cellCount)

    for idx in 0..<cellCount {
      let raw = rawCells[idx]
      guard raw > 0 else { continue }
      totalFilled += 1
      let px = idx % size
      let py = idx / size

      if raw == playerTag {
        activeCells += 1
        if px > 0 { edgeOfOwned[idx - 1] = true }
        if px < size - 1 { edgeOfOwned[idx + 1] = true }
        if py > 0 { edgeOfOwned[idx - size] = true }
        if py < size - 1 { edgeOfOwned[idx + size] = true }
      } else {
        if px > 0 { opponentEdge[idx - 1] = true }
        if px < size - 1 { opponentEdge[idx + 1] = true }
        if py > 0 { opponentEdge[idx - size] = true }
        if py < size - 1 { opponentEdge[idx + size] = true }
      }
    }

    // Own anchors
    for idx in 0..<cellCount {
      guard rawCells[idx] == playerTag else { continue }
      let px = idx % size
      let py = idx / size
      let diags = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
      for (dx, dy) in diags {
        guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
        let di = dy * size + dx
        if rawCells[di] == 0, !edgeOfOwned[di] {
          ownAnchors[di] = true
        }
      }
    }

    // Opponent anchors (union of all opponents)
    for idx in 0..<cellCount {
      let raw = rawCells[idx]
      guard raw > 0, raw != playerTag else { continue }
      let px = idx % size
      let py = idx / size
      let diags = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
      for (dx, dy) in diags {
        guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
        let di = dy * size + dx
        if rawCells[di] == 0, !opponentEdge[di] {
          opponentAnchorUnion[di] = true
        }
      }
    }

    self.edgeOfOwned = edgeOfOwned
    self.ownAnchors = ownAnchors
    self.opponentAnchorUnion = opponentAnchorUnion
    self.activeCellCount = activeCells
    self.isFirstMove = activeCells == 0
    let totalCells = Double(cellCount)
    self.progress = Double(totalFilled) / totalCells
    let meanCells = Double(totalFilled) / Double(max(1, playerCount))
    self.playerLead = (Double(activeCells) - meanCells) / totalCells
  }

  public init(state: GameState) {
    self.init(
      rawCells: state.board.rawCells,
      playerTag: state.activePlayerId.compactIndex,
      playerCount: state.turnOrder.count
    )
  }

  public init(boardEncoding: [UInt8], activePlayerTag: UInt8, playerCount: Int = 4) {
    self.init(rawCells: boardEncoding, playerTag: activePlayerTag, playerCount: playerCount)
  }
}

public enum MoveFeatureExtractor {
  public static let featureCount = 8

  private static let pieceCellCounts: [String: Int] = {
    Dictionary(uniqueKeysWithValues: PieceLibrary.pieces.map { ($0.id, $0.baseCells.count) })
  }()

  public static func extractMoveFeatures(
    action: CommandAction,
    context: BoardContext
  ) -> [Double] {
    switch action {
    case .pass:
      return [0, 0, 0, 0, 0, context.isFirstMove ? 1 : 0, context.progress, context.playerLead]

    case let .place(pieceId, variantId, origin):
      guard let piece = PieceLibrary.pieceById[pieceId],
        let variant = piece.variants[safe: variantId]
      else {
        return [0, 0, 0, 0, 0, context.isFirstMove ? 1 : 0, context.progress, context.playerLead]
      }

      let size = context.size
      let cellCount = piece.baseCells.count

      // Feature 0: pieceSize
      let pieceSize = Double(cellCount) / 5.0

      // Feature 1: centrality
      let center = Double(size - 1) / 2.0
      let dist = abs(Double(origin.x) - center) + abs(Double(origin.y) - center)
      let centrality = max(0, 1.0 - dist / (center * 2.0))

      // Collect absolute cell indices and build edge set for the placed piece
      var placedIndices: [Int] = []
      placedIndices.reserveCapacity(cellCount)
      var edgeOfPlaced = Set<Int>()

      for cell in variant {
        let px = origin.x + cell.x
        let py = origin.y + cell.y
        let idx = py * size + px
        placedIndices.append(idx)
        if px > 0 { edgeOfPlaced.insert(idx - 1) }
        if px < size - 1 { edgeOfPlaced.insert(idx + 1) }
        if py > 0 { edgeOfPlaced.insert(idx - size) }
        if py < size - 1 { edgeOfPlaced.insert(idx + size) }
      }
      let placedSet = Set(placedIndices)

      // Feature 2: newAnchorsCreated
      var newAnchors = 0
      var anchorSeen = Set<Int>()
      for cell in variant {
        let px = origin.x + cell.x
        let py = origin.y + cell.y
        let diags = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
        for (dx, dy) in diags {
          guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
          let di = dy * size + dx
          if !anchorSeen.contains(di),
            context.rawCells[di] == 0,
            !placedSet.contains(di),
            !context.edgeOfOwned[di],
            !context.ownAnchors[di],
            !edgeOfPlaced.contains(di)
          {
            anchorSeen.insert(di)
            newAnchors += 1
          }
        }
      }
      let newAnchorsNorm = Double(newAnchors) / 8.0

      // Feature 3: opponentAnchorsBlocked
      var blocked = 0
      for idx in placedIndices {
        if context.opponentAnchorUnion[idx] {
          blocked += 1
        }
      }
      let blockedNorm = Double(blocked) / 5.0

      // Feature 4: proximityToOwn
      var edgeContact = 0
      for idx in placedIndices {
        if context.edgeOfOwned[idx] {
          edgeContact += 1
        }
      }
      let proximityNorm = Double(edgeContact) / Double(max(1, cellCount))

      return [
        pieceSize,
        centrality,
        newAnchorsNorm,
        blockedNorm,
        proximityNorm,
        context.isFirstMove ? 1.0 : 0.0,
        context.progress,
        context.playerLead,
      ]
    }
  }

  public static func extractAllMoveFeatures(
    context: BoardContext,
    legalMoves: [CommandAction]
  ) -> [[Double]] {
    legalMoves.map { extractMoveFeatures(action: $0, context: context) }
  }
}
