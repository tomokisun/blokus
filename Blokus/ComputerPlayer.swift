import Foundation

struct CandidateMove {
  let piece: Piece
  let origin: Coordinate
  let rotation: Rotation
  let flipped: Bool
}

struct Candidate {
  let piece: Piece
  let origin: Coordinate
}

struct ComputerPlayer {
  let owner: PlayerColor
  let level: ComputerLevel
  
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getOwnedPieces(pieces: pieces)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    var candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
    
    switch level {
    case .easy:
      break
      
    case .normal:
      candidates = Dictionary(grouping: candidates, by: { $0.piece.baseShape.count })
        .mapValues { $0.shuffled() }
        .sorted(by: { $0.key > $1.key })
        .flatMap(\.value)
    }
    
    guard let candidate = candidates.first else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    var bestPiece = candidate.piece
    bestPiece.orientation = Orientation(rotation: candidate.rotation, flipped: candidate.flipped)
    return Candidate(piece: bestPiece, origin: candidate.origin)
  }
  
  private func getOwnedPieces(pieces: [Piece]) -> [Piece] {
    return pieces.filter { $0.owner == owner }
  }
  
  private func performPlacePirce(board: inout Board, pieces: inout [Piece], piece: Piece, at coordinate: Coordinate) {
    do {
      try board.placePiece(piece: piece, at: coordinate)
      if let idx = pieces.firstIndex(where: { $0.id == piece.id }) {
        pieces.remove(at: idx)
      }
      print("CPU(\(owner)) placed piece \(piece.id) at (\(coordinate.x), \(coordinate.y)) [\(level)]")
    } catch {
      print("Unexpected error in placing best move: \(error)")
    }
  }
  
  private func computeCandidateMoves(board: Board, pieces: [Piece]) -> [CandidateMove] {
    var candidates = [CandidateMove]()
    
    for piece in pieces {
      // ピースの全オリエンテーションを試す（回転4種 x flipped有無の2倍 = 8通り）
      for rotationCase in [Rotation.none, .ninety, .oneEighty, .twoSeventy] {
        for flippedCase in [false, true] {
          var testPiece = piece
          testPiece.orientation = Orientation(rotation: rotationCase, flipped: flippedCase)
          
          // ボード上の全マスを起点におけるか調べる
          for y in 0..<Board.height {
            for x in 0..<Board.width {
              let origin = Coordinate(x: x, y: y)
              if board.canPlacePiece(piece: testPiece, at: origin) {
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
    }
    return candidates
  }
}

