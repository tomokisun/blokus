import Foundation

actor ComputerHard: Computer {
  let owner: PlayerColor
  
  init(owner: PlayerColor) {
    self.owner = owner
  }
  
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let myPieces = getPlayerPieces(from: pieces, owner: owner)
    guard !myPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    // 最大ピースサイズ
    let maxPieceSize = myPieces.map(\.baseShape.count).max() ?? 0
    let currentCellsSize = getPlayerCells(from: board, owner: owner).count
    let theoreticalMax = Double(maxPieceSize * 2) + Double(currentCellsSize)
    
    print("maxPieceSize: \(maxPieceSize)")
    print("theoreticalMax: \(theoreticalMax)")
    
    var firstMoves = computeCandidateMoves(board: board, pieces: myPieces)
    firstMoves = Dictionary(grouping: firstMoves, by: { $0.piece.baseShape.count })
      .mapValues { $0.shuffled() }
      .sorted(by: { $0.key > $1.key })
      .flatMap(\.value)
    
    guard !firstMoves.isEmpty else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    var bestScore = -Double.infinity
    var bestMove: CandidateMove? = nil
    
    firstMoveLoop: for firstMove in firstMoves {
      // 初手シミュレーション
      var boardAfterFirst = board
      try? boardAfterFirst.placePiece(piece: applyOrientation(firstMove), at: firstMove.origin)
      
      // 相手はパス: boardAfterFirstそのまま
      
      // 2手目候補を計算
      let usedPieces = myPiecesAfterUsing(firstMove, from: myPieces)
      let secondMoves = computeCandidateMoves(board: boardAfterFirst, pieces: usedPieces)
      
      if secondMoves.isEmpty {
        // 2手目なし: この時点での占有数
        let myCells = getPlayerCells(from: boardAfterFirst, owner: owner)
        let score = Double(myCells.count)
        if score > bestScore {
          bestScore = score
          bestMove = firstMove
        }
        // 理論値到達チェック(2手目なしでも最大化は難しいが一応)
        if score == theoreticalMax {
          // 理論値達成 ⇒ 即終了
          break firstMoveLoop
        }
      } else {
        var bestSecondScore = -Double.infinity
        secondMoveLoop: for secondMove in secondMoves {
          var boardAfterSecond = boardAfterFirst
          try? boardAfterSecond.placePiece(piece: applyOrientation(secondMove), at: secondMove.origin)
          
          let myCells = getPlayerCells(from: boardAfterSecond, owner: owner)
          let score = Double(myCells.count)
          print("score: \(score)")
          if score > bestSecondScore {
            bestSecondScore = score
          }
          // 理論値到達チェック
          if score == theoreticalMax {
            bestSecondScore = score
            break secondMoveLoop
          }
        }
        
        // bestSecondScoreがこの初手に対する最良2手目スコア
        if bestSecondScore > bestScore {
          bestScore = bestSecondScore
          bestMove = firstMove
        }
        if bestScore == theoreticalMax {
          // 理論値達成 ⇒ 他の初手を見る必要なし
          break firstMoveLoop
        }
      }
    }
    
    guard let finalMove = bestMove else {
      print("CPU(\(owner)) cannot find beneficial move, passes.")
      return nil
    }
    
    return makeCandidate(for: finalMove)
  }
  
  // 使用したmove.pieceを取り除く
  func myPiecesAfterUsing(_ move: CandidateMove, from: [Piece]) -> [Piece] {
    return from.filter { $0.id != move.piece.id }
  }
  
  func applyOrientation(_ move: CandidateMove) -> Piece {
    var p = move.piece
    p.orientation = Orientation(rotation: move.rotation, flipped: move.flipped)
    return p
  }
}
