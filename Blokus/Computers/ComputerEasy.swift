import Foundation

actor ComputerEasy: Computer {
  let owner: PlayerColor

  init(owner: PlayerColor) {
    self.owner = owner
  }

  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getOwnedPieces(pieces: pieces)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    let candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
      .shuffled()
    
    guard let candidate = candidates.first else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    return makeCandidate(for: candidate)
  }
}
