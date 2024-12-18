import Foundation

/// `ComputerPlayer` は、指定されたオーナー(プレイヤー色)と思考レベルをもとに、
/// ボード上でコマを最適に配置する手を計算するエージェントです。
actor ComputerNormal: Computer {
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
