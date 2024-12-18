import Foundation

actor ComputerHard: Computer {
  let owner: PlayerColor

  init(owner: PlayerColor) {
    self.owner = owner
  }
  
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getPlayerPieces(from: pieces, owner: owner)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    let candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
    let evaluated = evaluateHardCandidates(candidates, board: board)

    guard let candidate = evaluated.first else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    return makeCandidate(for: candidate)
  }
  
  // MARK: - Hard Level Private Helpers
  
  /// Hardレベル用の候補手評価メソッド
  ///
  /// Normalレベルの基準（サイズでの優先）に加え、
  /// 自身のコマとの角接触が多い候補手をより優先します。
  ///
  /// - Parameters:
  ///   - candidates: 元となる候補手一覧
  ///   - board: 現在のボード状態
  /// - Returns: Hardレベルに基づいてソートした候補手一覧
  private func evaluateHardCandidates(_ candidates: [CandidateMove], board: Board) -> [CandidateMove] {
    let playerCells = getPlayerCells(from: board, owner: owner)
    
    // 各候補手に対して、(CandidateMove, 角接触数) をタプルで持たせる
    let scoredCandidates = candidates.map { candidate -> (CandidateMove, Int) in
      let piece = candidateToPiece(candidate: candidate)
      let coords = computeFinalCoordinates(for: piece, at: candidate.origin)
      let diagonalCount = coords.reduce(0) { sum, coord in
        sum + diagonalTouchCount(coord, playerCells: playerCells)
      }
      return (candidate, diagonalCount)
    }
    
    // ソート基準:
    // 1. ピースサイズ大きい方が上位
    // 2. 同プレイヤーセルとの角接触数が多い方が上位
    return scoredCandidates.sorted { a, b in
      let aSize = a.0.piece.baseShape.count
      let bSize = b.0.piece.baseShape.count
      if aSize == bSize {
        return a.1 > b.1
      } else {
        return aSize > bSize
      }
    }.map { $0.0 }
  }
  
  /// 候補手(`CandidateMove`)から実際の `Piece` インスタンス（正しいオリエンテーション付き）を生成します。
  private func candidateToPiece(candidate: CandidateMove) -> Piece {
    var piece = candidate.piece
    piece.orientation = Orientation(rotation: candidate.rotation, flipped: candidate.flipped)
    return piece
  }
  
  /// ピースを指定座標へ置いた場合の占有セル群を計算します。
  private func computeFinalCoordinates(for piece: Piece, at origin: Coordinate) -> [Coordinate] {
    let shape = piece.transformedShape()
    return shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
  }
  
  /// 指定セルがプレイヤーセルと何箇所の斜め方向で接触しているか数えます。
  private func diagonalTouchCount(_ coord: Coordinate, playerCells: Set<Coordinate>) -> Int {
    let neighborsDiagonal = [
      Coordinate(x: coord.x-1, y: coord.y-1),
      Coordinate(x: coord.x+1, y: coord.y-1),
      Coordinate(x: coord.x-1, y: coord.y+1),
      Coordinate(x: coord.x+1, y: coord.y+1)
    ]
    return neighborsDiagonal.filter { playerCells.contains($0) }.count
  }
}
