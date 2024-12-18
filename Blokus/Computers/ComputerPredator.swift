import Foundation
import Combine

actor ComputerPredator: Computer {
  let owner: PlayerColor
  
  private let maxDepth: Int = 3

  private let progressSubject = PassthroughSubject<Double, Never>()
  
  private var exploredNodes = 0
  private var totalNodes = 0

  init(owner: PlayerColor) {
    self.owner = owner
  }
  
  var progressPublisher: AnyPublisher<Double, Never> {
    progressSubject.eraseToAnyPublisher()
  }
  
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getPlayerPieces(from: pieces, owner: owner)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    var candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
    if candidates.count > 20 {
      candidates = candidates.filter { $0.piece.baseShape.count >= 5 }
        .suffix(5)
        .compactMap { $0 }
    }
    guard !candidates.isEmpty else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    // 総ノード数を近似計算
    totalNodes = approximateTotalNodes(candidatesCount: candidates.count, depth: maxDepth)
    exploredNodes = 0
    updateProgress() // 開始時0%
    
    var bestScore = Int.min
    var bestCandidate: CandidateMove? = nil
    var alpha = Int.min
    var beta = Int.max
    
    for candidate in candidates {
      var newBoard = board
      var newPieces = pieces
      applyCandidate(candidate, board: &newBoard, pieces: &newPieces)
      
      let score = minimax(board: newBoard, allPieces: newPieces, depth: 1, alpha: &alpha, beta: &beta, currentPlayer: nextPlayer(after: owner))
      
      if score > bestScore {
        bestScore = score
        bestCandidate = candidate
      }
      
      alpha = max(alpha, bestScore)
      if beta <= alpha {
        break
      }
    }
    
    return bestCandidate.map { makeCandidate(for: $0) }
  }
  
  // MARK: - Minimax & Alpha-Beta
  
  private func minimax(board: Board,
                       allPieces: [Piece],
                       depth: Int,
                       alpha: inout Int,
                       beta: inout Int,
                       currentPlayer: PlayerColor) -> Int {
    exploredNodes += 1
    updateProgress()
    
    if depth >= maxDepth || isGameOver(board: board, pieces: allPieces) {
      return evaluate(board: board)
    }
    
    let currentPlayerPieces = getPlayerPieces(from: allPieces, owner: currentPlayer)
    var moves = computeCandidateMoves(board: board, pieces: currentPlayerPieces)
    if moves.count > 20 {
      moves = moves.filter { $0.piece.baseShape.count >= 5 }
        .suffix(5)
        .compactMap { $0 }
    }
    
    if moves.isEmpty {
      let next = nextPlayer(after: currentPlayer)
      return minimax(board: board, allPieces: allPieces, depth: depth+1, alpha: &alpha, beta: &beta, currentPlayer: next)
    }
    
    if currentPlayer == owner {
      // Maximizer
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
          break
        }
      }
      return bestVal
    } else {
      // Minimizer
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
          break
        }
      }
      return bestVal
    }
  }
  
  // MARK: - ヒューリスティック評価
  
  private func evaluate(board: Board) -> Int {
    // 1. 自分のセル数
    let ownerCells = boardCells(for: owner, board: board)
    let ownerScore = ownerCells.count
    
    // 2. 潜在的な配置可能ポイント数（角接触ポイント）
    let potentialPlacements = countPotentialPlacements(for: owner, board: board)
    
    // 3. 相手との距離
    let distanceScore = averageDistanceToOpponents(ownerCells: ownerCells, board: board, owner: owner)
    
    // 4. 相手の得点(セル数)合計
    let others = PlayerColor.allCases.filter { $0 != owner }
    let othersScoreSum = others.map { board.score(for: $0) }.reduce(0, +)
    
    // 重みづけは仮例:
    //   自セル数に重点: 10倍
    //   潜在的配置ポイント: 5倍
    //   相手との距離: 2倍
    //   相手スコア合計は不利要因なので引き算
    let score = (ownerScore * 10)
                + (potentialPlacements * 5)
                + (distanceScore * 2)
                - (othersScoreSum * 8)
    
    print("Score[\(owner.rawValue)]: \(score)", ownerScore, potentialPlacements, distanceScore, othersScoreSum)
    return score
  }
  
  // 自分のセル座標セットを取得
  private func boardCells(for player: PlayerColor, board: Board) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for y in 0..<Board.height {
      for x in 0..<Board.width {
        if case let .occupied(owner) = board.cells[x][y], owner == player {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
  }
  
  /// 潜在的配置ポイント数を測定
  /// 簡易的には自分の領域から斜め接触可能な空セル数をカウントする
  private func countPotentialPlacements(for player: PlayerColor, board: Board) -> Int {
    let playerCells = boardCells(for: player, board: board)
    var potentialPoints = Set<Coordinate>()
    for cell in playerCells {
      for diag in diagonalNeighbors(of: cell) {
        if board.isValidCoordinate(diag),
           case .empty = board.cells[diag.x][diag.y] {
          potentialPoints.insert(diag)
        }
      }
    }
    return potentialPoints.count
  }
  
  private func diagonalNeighbors(of coord: Coordinate) -> [Coordinate] {
    return [
      Coordinate(x: coord.x-1, y: coord.y-1),
      Coordinate(x: coord.x+1, y: coord.y-1),
      Coordinate(x: coord.x-1, y: coord.y+1),
      Coordinate(x: coord.x+1, y: coord.y+1)
    ]
  }

  /// 相手領域との距離
  /// 自分セルの各セルについて、もっとも近い相手セルまでのマンハッタン距離を計測し、その平均をとる
  /// 平均距離が大きいほど安全な領域が確保できているとみなす。
  private func averageDistanceToOpponents(ownerCells: Set<Coordinate>, board: Board, owner: PlayerColor) -> Int {
    let opponentCells = PlayerColor.allCases.filter({ $0 != owner }).flatMap {
      boardCells(for: $0, board: board)
    }
    guard !opponentCells.isEmpty else {
      // 相手のコマがなければ距離は最大としよう(適当な大きめ値)
      return 10
    }
    
    var sumDistance = 0
    for oc in ownerCells {
      let dist = opponentCells.map { manhattanDistance($0, oc) }.min() ?? 0
      sumDistance += dist
    }
    return ownerCells.isEmpty ? 0 : sumDistance / ownerCells.count
  }
  
  private func manhattanDistance(_ a: Coordinate, _ b: Coordinate) -> Int {
    return abs(a.x - b.x) + abs(a.y - b.y)
  }
  
  // MARK: - State Check & Apply
  
  private func applyCandidate(_ candidate: CandidateMove, board: inout Board, pieces: inout [Piece]) {
    var appliedPiece = candidate.piece
    appliedPiece.orientation = Orientation(rotation: candidate.rotation, flipped: candidate.flipped)
    do {
      try board.placePiece(piece: appliedPiece, at: candidate.origin)
      if let idx = pieces.firstIndex(where: { $0.id == appliedPiece.id }) {
        pieces.remove(at: idx)
      }
    } catch {
      // ignore
    }
  }
  
  private func isGameOver(board: Board, pieces: [Piece]) -> Bool {
    for player in PlayerColor.allCases {
      let playerPieces = getPlayerPieces(from: pieces, owner: player)
      if !playerPieces.isEmpty {
        var moves = computeCandidateMoves(board: board, pieces: playerPieces)
        if moves.count > 20 {
          moves = moves.filter { $0.piece.baseShape.count >= 5 }
            .suffix(5)
            .compactMap { $0 }
        }
        if !moves.isEmpty {
          return false
        }
      }
    }
    return true
  }

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
  
  private func approximateTotalNodes(candidatesCount: Int, depth: Int) -> Int {
    return Int(pow(Double(candidatesCount), Double(depth + 1)))
  }
  
  private func updateProgress() {
    let progress = totalNodes > 0 ? Double(exploredNodes) / Double(totalNodes) : 0.0
    progressSubject.send(progress)
  }
}
