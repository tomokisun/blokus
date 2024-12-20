import Foundation

actor ComputerNormal: Computer {
  let owner: Player

  init(owner: Player) {
    self.owner = owner
  }
  
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getPlayerPieces(from: pieces, owner: owner)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    var candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
    
    candidates = Dictionary(grouping: candidates, by: { $0.piece.baseShape.count })
      .mapValues { $0.shuffled() }
      .sorted(by: { $0.key > $1.key })
      .flatMap(\.value)
    
    guard let candidate = candidates.first else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    return makeCandidate(for: candidate)
  }
}
