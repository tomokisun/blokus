import Foundation

/// `ComputerPlayer` は、指定されたオーナー(プレイヤー色)と思考レベルをもとに、
/// ボード上でコマを最適に配置する手を計算するエージェントです。
actor ComputerPlayer {
  
  /// コンピュータプレイヤーのオーナー（プレイヤー色）。
  let owner: PlayerColor
  
  /// コンピュータプレイヤーの思考レベル。`easy`または`normal`を想定。
  let level: ComputerLevel
  
  /// イニシャライザ
  ///
  /// - Parameters:
  ///   - owner: コンピュータプレイヤーの所有者（プレイヤー色）
  ///   - level: コンピュータプレイヤーの思考レベル
  init(owner: PlayerColor, level: ComputerLevel) {
    self.owner = owner
    self.level = level
  }
  
  /// コンピュータプレイヤーが次に行うべき配置手を計算して返します。
  /// ボード上に配置できる最適な候補を探索し、思考レベルに応じたフィルタリングを行います。
  ///
  /// - Parameters:
  ///   - board: 現在のボード状態
  ///   - pieces: 現在使用可能なピースの配列
  /// - Returns: 選択された配置候補(`Candidate`)。配置不可能な場合は`nil`を返します。
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate? {
    let ownerPieces = getOwnedPieces(pieces: pieces)
    guard !ownerPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return nil
    }
    
    // 配置候補手を算出
    var candidates = computeCandidateMoves(board: board, pieces: ownerPieces)
    
    // 思考レベルに応じて候補を処理
    switch level {
    case .easy:
      // Easy: 候補をランダムにシャッフル
      candidates = candidates.shuffled()
      
    case .normal:
      // Normal: ピースの baseShape.count（形状のセル数）に応じてソートし、
      // 大きなコマほど優先する。その後、各グループ内はシャッフル。
      candidates = Dictionary(grouping: candidates, by: { $0.piece.baseShape.count })
        .mapValues { $0.shuffled() }
        .sorted(by: { $0.key > $1.key })
        .flatMap(\.value)
    }
    
    guard let candidate = candidates.first else {
      print("CPU(\(owner)) cannot place any piece and passes.")
      return nil
    }
    
    // 選ばれた候補に応じてピースのオリエンテーションを更新
    var bestPiece = candidate.piece
    bestPiece.orientation = Orientation(rotation: candidate.rotation, flipped: candidate.flipped)
    return Candidate(piece: bestPiece, origin: candidate.origin)
  }
  
  /// コンピュータ所有のピースだけを抽出します。
  ///
  /// - Parameter pieces: 全てのピース配列
  /// - Returns: `owner`に紐づくピース配列
  private func getOwnedPieces(pieces: [Piece]) -> [Piece] {
    return pieces.filter { $0.owner == owner }
  }

  /// 配置可能な全ての候補手を算出します。
  /// ピースの全ての回転・反転組み合わせ(8通り)を試し、ボード上の全座標で
  /// 配置可能かどうかをチェックして候補手リストを作成します。
  ///
  /// - Parameters:
  ///   - board: 現在のボード状態
  ///   - pieces: コンピュータプレイヤーが所有するピース配列
  /// - Returns: 配置可能な全候補手の配列
  private func computeCandidateMoves(board: Board, pieces: [Piece]) -> [CandidateMove] {
    var candidates = [CandidateMove]()
    
    for piece in pieces {
      // 回転4種 × flipped有無2種 = 8通りのオリエンテーションを試行
      for rotationCase in [Rotation.none, .ninety, .oneEighty, .twoSeventy] {
        for flippedCase in [false, true] {
          var testPiece = piece
          testPiece.orientation = Orientation(rotation: rotationCase, flipped: flippedCase)
          
          // ボード上の全マスを起点に配置可能性をチェック
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
