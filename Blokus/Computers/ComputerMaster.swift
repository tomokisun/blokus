import Foundation

/// minimax法とアルファベータ法を使ったコンピュータの思考ロジック
actor ComputerMaster: Computer {
  let owner: PlayerColor
  
  /// 深さ制限（必要に応じて調整）
  private let maxDepth: Int = 3
  
  /// 現在探索中のノード数
  private var exploredNodes = 0
  
  /// 総ノード数（探索開始前に計算）
  private var totalNodes = 0
  
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
    guard !candidates.isEmpty else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    // Minimax探索前に総ノード数を見積もる（簡易的な例）
    // 総ノード数 = 現手番の候補手数 * 各候補後に展開する子ノード数概算
    // ここでは雑に candidates.count * (ある程度の期待手数^(maxDepth)) とする
    // 実際には正確な総数を事前計算するのは難しいため、近似でよい。
    totalNodes = approximateTotalNodes(candidatesCount: candidates.count, depth: maxDepth)
    exploredNodes = 0
    updateProgress() // 開始時0%
    print("totalNodes", totalNodes)
    
    // Minimaxで最善手を探索
    var bestScore = Int.min
    var bestCandidate: CandidateMove? = nil
    var alpha = Int.min
    var beta = Int.max
    
    for candidate in candidates {
      // 仮想的に候補手を打ってみる
      var newBoard = board
      var newPieces = pieces
      applyCandidate(candidate, board: &newBoard, pieces: &newPieces)
      
      // 次のプレイヤーへ手番を渡して評価（深さ1から始める）
      let score = minimax(board: newBoard, allPieces: newPieces, depth: 1, alpha: &alpha, beta: &beta, currentPlayer: nextPlayer(after: owner))
      
      if score > bestScore {
        bestScore = score
        bestCandidate = candidate
      }
      
      alpha = max(alpha, bestScore)
      if beta <= alpha {
        break // アルファ・ベータ枝刈り
      }
    }
    
    guard let chosen = bestCandidate else {
      return nil
    }
    return makeCandidate(for: chosen)
  }
  
  // MARK: - Minimax & Alpha-Beta
  
  /// Minimax関数：currentPlayerの手番での局面(board, allPieces)を評価する
  private func minimax(board: Board,
                       allPieces: [Piece],
                       depth: Int,
                       alpha: inout Int,
                       beta: inout Int,
                       currentPlayer: PlayerColor) -> Int {
    exploredNodes += 1
    updateProgress()

    // 深さ制限またはゲーム終了条件に達した場合は局面を評価
    if depth >= maxDepth || isGameOver(board: board, pieces: allPieces) {
      return evaluate(board: board)
    }
    
    let currentPlayerPieces = getPlayerPieces(from: allPieces, owner: currentPlayer)
    let moves = computeCandidateMoves(board: board, pieces: currentPlayerPieces)
    
    // 手がない場合、パス
    if moves.isEmpty {
      // パスして次のプレイヤーへ
      let next = nextPlayer(after: currentPlayer)
      return minimax(board: board, allPieces: allPieces, depth: depth+1, alpha: &alpha, beta: &beta, currentPlayer: next)
    }
    
    if currentPlayer == owner {
      // オーナーの手番（Maximizer）
      var bestVal = Int.min
      
      for move in moves {
        var newBoard = board
        var newPieces = allPieces
        applyCandidate(move, board: &newBoard, pieces: &newPieces)
        
        let next = nextPlayer(after: currentPlayer)
        let value = minimax(board: newBoard, allPieces: newPieces, depth: depth+1, alpha: &alpha, beta: &beta, currentPlayer: next)
        bestVal = max(bestVal, value)
        
        alpha = max(alpha, bestVal)
        if beta <= alpha {
          break // 枝刈り
        }
      }
      return bestVal
    } else {
      // 他プレイヤーの手番（Minimizer）
      var bestVal = Int.max
      
      for move in moves {
        var newBoard = board
        var newPieces = allPieces
        applyCandidate(move, board: &newBoard, pieces: &newPieces)
        
        let next = nextPlayer(after: currentPlayer)
        let value = minimax(board: newBoard, allPieces: newPieces, depth: depth+1, alpha: &alpha, beta: &beta, currentPlayer: next)
        bestVal = min(bestVal, value)
        
        beta = min(beta, bestVal)
        if beta <= alpha {
          break // 枝刈り
        }
      }
      return bestVal
    }
  }
  
  // MARK: - Helpers
  
  /// 候補手を実際に盤面・ピース配列に適用
  private func applyCandidate(_ candidate: CandidateMove, board: inout Board, pieces: inout [Piece]) {
    var appliedPiece = candidate.piece
    appliedPiece.orientation = Orientation(rotation: candidate.rotation, flipped: candidate.flipped)
    do {
      try board.placePiece(piece: appliedPiece, at: candidate.origin)
      if let idx = pieces.firstIndex(where: { $0.id == appliedPiece.id }) {
        pieces.remove(at: idx)
      }
    } catch {
      // 配置失敗は起こらないはずだが、一応無視
    }
  }
  
  /// 現在の局面を評価する簡易関数
  /// ownerのスコア - 他プレイヤーのスコア合計
  private func evaluate(board: Board) -> Int {
    let ownerScore = board.score(for: owner)
    let otherPlayers = PlayerColor.allCases.filter { $0 != owner }
    let otherScore = otherPlayers.reduce(0) { $0 + board.score(for: $1) }
    return ownerScore - otherScore
  }
  
  /// ゲーム終了状態判定（簡易版）
  /// ここでは「全プレイヤーが置けるピースがない場合」をゲーム終了とみなす
  private func isGameOver(board: Board, pieces: [Piece]) -> Bool {
    for player in PlayerColor.allCases {
      let playerPieces = getPlayerPieces(from: pieces, owner: player)
      if !playerPieces.isEmpty {
        let moves = computeCandidateMoves(board: board, pieces: playerPieces)
        if !moves.isEmpty {
          // このプレイヤーがまだ置けるならゲームは続行可能
          return false
        }
      }
    }
    return true
  }

  /// 次のプレイヤーを取得する。
  /// この例では順番を [red -> blue -> green -> yellow -> red ...] と想定。
  private func nextPlayer(after player: PlayerColor) -> PlayerColor {
    switch player {
    case .red:
      return .blue
    case .blue:
      return .green
    case .green:
      return .yellow
    case .yellow:
      return .red
    }
  }
  
  /// 総ノード数を近似計算するメソッド（例：単純な指数近似）
  private func approximateTotalNodes(candidatesCount: Int, depth: Int) -> Int {
    // ここでは簡易的に candidatesCount^(depth+1) 程度で近似する
    return Int(pow(Double(candidatesCount), Double(depth + 1)))
  }
  
  /// 進捗更新メソッド
  private func updateProgress() {
    let progress = totalNodes > 0 ? Double(exploredNodes) / Double(totalNodes) : 0.0
    print(progress)
  }
}
