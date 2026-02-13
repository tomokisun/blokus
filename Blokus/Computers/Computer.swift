import Foundation

protocol Computer: Actor {
  var owner: Player { get }
  
  init(owner: Player)
  
  /// Calculates the next move for the AI player.
  /// It searches legal candidates and applies filtering based on reasoning level.
  ///
  /// - Parameters:
  ///   - board: Current board state.
  ///   - pieces: Currently available piece list.
  /// - Returns: Selected `Candidate`. Returns `nil` when no legal move exists.
  func moveCandidate(board: Board, pieces: [Piece]) async -> Candidate?
}

extension Computer {
  func makeCandidate(for move: CandidateMove) -> Candidate {
    var bestPiece = move.piece
    bestPiece.orientation = Orientation(rotation: move.rotation, flipped: move.flipped)
    return Candidate(piece: bestPiece, origin: move.origin)
  }
  
  func getPlayerPieces(from pieces: [Piece], owner: Player) -> [Piece] {
    return pieces.filter { $0.owner == owner }
  }
  
  /// Returns all cells that belong to the specified player.
  func getPlayerCells(from board: Board, owner: Player) -> Set<Coordinate> {
    board.playerCells(owner: owner)
  }
  
  /// Computes all candidate moves.
  /// Tries 8 orientation combinations (4 rotations × flip) and checks every board coordinate.
  ///
  /// - Parameters:
  ///   - board: Current board state.
  ///   - pieces: Piece list owned by the AI player.
  /// - Returns: All legal candidate moves.
  func computeCandidateMoves(board: Board, pieces: [Piece]) -> [CandidateMove] {
    var candidates = [CandidateMove]()
    
    for piece in pieces {
      // Generate unique piece orientations.
      let uniqueOrientations = generateUniqueOrientations(for: piece)
      
      // Evaluate each candidate orientation.
      for (rotationCase, flippedCase, _) in uniqueOrientations {
        var testPiece = piece
        testPiece.orientation = Orientation(rotation: rotationCase, flipped: flippedCase)
        
        // Scan all board coordinates.
        for x in 0..<Board.width {
          for y in 0..<Board.height {
            let origin = Coordinate(x: x, y: y)
            if BoardLogic.canPlacePiece(piece: testPiece, at: origin, in: board) {
              candidates.append(
                CandidateMove(
                  piece: piece,
                  origin: origin,
                  rotation: rotationCase,
                  flipped: flippedCase
                )
              )
            }
          }
        }
      }
    }
    return candidates
  }
  
  /// Generates all 8 shapes (4 rotations × flip on/off) and removes duplicates.
  /// Returned tuple: `(rotation, flipped, normalizedShapeCoordinates)`.
  private func generateUniqueOrientations(for piece: Piece) -> [(Rotation, Bool, Set<Coordinate>)] {
    let rotations: [Rotation] = [.none, .ninety, .oneEighty, .twoSeventy]
    let flips: [Bool] = [false, true]
    
    var seenShapes = Set<Set<Coordinate>>()
    var results = [(Rotation, Bool, Set<Coordinate>)]()
    
    for r in rotations {
      for f in flips {
        var testPiece = piece
        testPiece.orientation = Orientation(rotation: r, flipped: f)
        let transformed = testPiece.transformedShape()
        
        // Normalize coordinates so relative position can be compared consistently.
        let normalized = normalizeShapeCoordinates(transformed)
        if !seenShapes.contains(normalized) {
          seenShapes.insert(normalized)
          results.append((r, f, normalized))
        }
      }
    }
    
    return results
  }
  
  /// Normalizes a set of coordinates.
  /// Translates the shape so that the minimum x/y become zero for comparison.
  private func normalizeShapeCoordinates(_ coords: [Coordinate]) -> Set<Coordinate> {
    let minX = coords.map(\.x).min() ?? 0
    let minY = coords.map(\.y).min() ?? 0
    let shifted = coords.map { Coordinate(x: $0.x - minX, y: $0.y - minY) }
    return Set(shifted)
  }
}
