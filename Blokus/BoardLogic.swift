import Foundation

enum BoardLogic {
  static func score(for player: Player, in board: Board) -> Int {
    board.playerCells(owner: player).count
  }

  static func hasPlaceableMove(for player: Player, pieces: [Piece], in board: Board) -> Bool {
    let ownerPieces = pieces.filter { $0.owner == player }
    for piece in ownerPieces {
      for testPiece in uniqueTransformations(for: piece) {
        for x in 0..<Board.width {
          for y in 0..<Board.height {
            if canPlacePiece(piece: testPiece, at: Coordinate(x: x, y: y), in: board) {
              return true
            }
          }
        }
      }
    }

    return false
  }

  static func isValidCoordinate(_ coordinate: Coordinate, in _: Board) -> Bool {
    return coordinate.x >= 0 && coordinate.x < Board.width && coordinate.y >= 0 && coordinate.y < Board.height
  }

  static func placePiece(
    piece: Piece,
    at origin: Coordinate,
    in board: Board
  ) throws(PlacementError) -> Board {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    try validatePlacement(piece: piece, finalCoords: finalCoords, in: board)

    var updatedBoard = board
    for coordinate in finalCoords {
      updatedBoard.setOwner(piece.owner, at: coordinate)
    }
    return updatedBoard
  }

  static func canPlacePiece(piece: Piece, at origin: Coordinate, in board: Board) -> Bool {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    do {
      try validatePlacement(piece: piece, finalCoords: finalCoords, in: board)
      return true
    } catch {
      return false
    }
  }

  static func highlightPossiblePlacements(for piece: Piece, in board: Board) -> Set<Coordinate> {
    var highlights: Set<Coordinate> = []

    for x in 0..<Board.width {
      for y in 0..<Board.height {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin, in: board) {
          let finalCoords = computeFinalCoordinates(for: piece, at: origin)
          highlights.formUnion(finalCoords)
        }
      }
    }

    return highlights
  }

  static func findNearestValidOrigin(
    for piece: Piece,
    near target: Coordinate,
    in board: Board
  ) -> Coordinate? {
    var bestOrigin: Coordinate?
    var bestDistance = Int.max

    for x in 0..<Board.width {
      for y in 0..<Board.height {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin, in: board) {
          let finalCoords = computeFinalCoordinates(for: piece, at: origin)
          let minDist = finalCoords.map { coord in
            let dx = coord.x - target.x
            let dy = coord.y - target.y
            return dx * dx + dy * dy
          }.min() ?? Int.max

          if minDist < bestDistance {
            bestDistance = minDist
            bestOrigin = origin
          }
        }
      }
    }

    return bestOrigin
  }

  static func findNearestValidOrigins(
    for piece: Piece,
    near target: Coordinate,
    in board: Board
  ) -> [Coordinate] {
    struct Scored {
      let origin: Coordinate
      let cellDist: Int    // primary: min cell-to-tap distance
      let originDist: Int  // secondary: origin-to-tap distance
    }

    var scored: [Scored] = []

    for x in 0..<Board.width {
      for y in 0..<Board.height {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin, in: board) {
          let finalCoords = computeFinalCoordinates(for: piece, at: origin)
          let cellDist = finalCoords.map { coord in
            let dx = coord.x - target.x
            let dy = coord.y - target.y
            return dx * dx + dy * dy
          }.min() ?? Int.max

          let odx = origin.x - target.x
          let ody = origin.y - target.y
          let originDist = odx * odx + ody * ody

          scored.append(Scored(origin: origin, cellDist: cellDist, originDist: originDist))
        }
      }
    }

    guard let best = scored.min(by: { ($0.cellDist, $0.originDist) < ($1.cellDist, $1.originDist) }) else {
      return []
    }

    return scored
      .filter { $0.cellDist == best.cellDist && $0.originDist == best.originDist }
      .map(\.origin)
  }

  static func startingCorner(for player: Player) -> Coordinate {
    switch player {
    case .red:
      return Coordinate(x: 0, y: 0)
    case .blue:
      return Coordinate(x: Board.width - 1, y: 0)
    case .green:
      return Coordinate(x: Board.width - 1, y: Board.height - 1)
    case .yellow:
      return Coordinate(x: 0, y: Board.height - 1)
    }
  }

  static func computeFinalCoordinates(
    for piece: Piece,
    at origin: Coordinate
  ) -> [Coordinate] {
    let shape = piece.transformedShape()
    return shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
  }

  private static func validatePlacement(
    piece: Piece,
    finalCoords: [Coordinate],
    in board: Board
  ) throws(PlacementError) {
    try checkBasicPlacementRules(finalCoords: finalCoords, in: board)
    let isFirstMove = !hasPlacedFirstPiece(for: piece.owner, in: board)

    if isFirstMove {
      try checkFirstPlacement(piece: piece, finalCoords: finalCoords)
    } else {
      try checkSubsequentPlacement(piece: piece, finalCoords: finalCoords, in: board)
    }
  }

  private static func checkBasicPlacementRules(
    finalCoords: [Coordinate],
    in board: Board
  ) throws(PlacementError) {
    for coordinate in finalCoords {
      guard board.isInside(coordinate) else {
        throw PlacementError.outOfBounds
      }
      guard board.cell(at: coordinate)?.owner == nil else {
        throw PlacementError.cellOccupied
      }
    }
  }

  private static func checkFirstPlacement(
    piece: Piece,
    finalCoords: [Coordinate]
  ) throws(PlacementError) {
    let corner = startingCorner(for: piece.owner)
    if !finalCoords.contains(corner) {
      throw PlacementError.firstMoveMustIncludeCorner
    }
  }

  private static func checkSubsequentPlacement(
    piece: Piece,
    finalCoords: [Coordinate],
    in board: Board
  ) throws(PlacementError) {
    let playerCells = board.playerCells(owner: piece.owner)

    var hasCornerTouch = false
    var hasEdgeTouch = false

    for finalCoordinate in finalCoords {
      if hasCornerAdjacency(from: finalCoordinate, playerCells: playerCells) {
        hasCornerTouch = true
      }
      if hasEdgeAdjacency(from: finalCoordinate, playerCells: playerCells) {
        hasEdgeTouch = true
      }
    }

    if !hasCornerTouch {
      throw PlacementError.mustTouchOwnPieceByCorner
    }
    if hasEdgeTouch {
      throw PlacementError.cannotShareEdgeWithOwnPiece
    }
  }

  private static func hasCornerAdjacency(from coordinate: Coordinate, playerCells: Set<Coordinate>) -> Bool {
    coordinate.diagonalNeighbors().contains(where: { playerCells.contains($0) })
  }

  private static func hasEdgeAdjacency(
    from coordinate: Coordinate,
    playerCells: Set<Coordinate>
  ) -> Bool {
    coordinate.edgeNeighbors().contains(where: { playerCells.contains($0) })
  }

  private static func hasPlacedFirstPiece(for player: Player, in board: Board) -> Bool {
    let coordinate = startingCorner(for: player)
    let cell = board.cell(at: coordinate)
    return cell?.owner == player
  }

  private static func uniqueTransformations(for piece: Piece) -> [Piece] {
    let rotations: [Rotation] = [.none, .ninety, .oneEighty, .twoSeventy]
    let flips: [Bool] = [false, true]

    var seenShapes = Set<Set<Coordinate>>()
    var result: [Piece] = []

    for rotation in rotations {
      for flipped in flips {
        var testPiece = piece
        testPiece.orientation = Orientation(rotation: rotation, flipped: flipped)
        let normalized = normalizeShapeCoordinates(testPiece.transformedShape())

        if !seenShapes.contains(normalized) {
          seenShapes.insert(normalized)
          result.append(testPiece)
        }
      }
    }

    return result
  }

  private static func normalizeShapeCoordinates(_ coordinates: [Coordinate]) -> Set<Coordinate> {
    let minX = coordinates.map(\.x).min() ?? 0
    let minY = coordinates.map(\.y).min() ?? 0
    return Set(coordinates.map { Coordinate(x: $0.x - minX, y: $0.y - minY) })
  }
}
