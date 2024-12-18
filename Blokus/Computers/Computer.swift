import Foundation

protocol Computer: Actor {
  var owner: PlayerColor { get }
  
  init(owner: PlayerColor)
  
  /// コンピュータプレイヤーが次に行うべき配置手を計算して返します。
  /// ボード上に配置できる最適な候補を探索し、思考レベルに応じたフィルタリングを行います。
  ///
  /// - Parameters:
  ///   - board: 現在のボード状態
  ///   - pieces: 現在使用可能なピースの配列
  /// - Returns: 選択された配置候補(`Candidate`)。配置不可能な場合は`nil`を返します。
  func moveCandidate(board: Board, pieces: [Piece]) -> Candidate?
}

extension Computer {
  func makeCandidate(for move: CandidateMove) -> Candidate {
    var bestPiece = move.piece
    bestPiece.orientation = Orientation(rotation: move.rotation, flipped: move.flipped)
    return Candidate(piece: bestPiece, origin: move.origin)
  }

  /// コンピュータ所有のピースだけを抽出します。
  ///
  /// - Parameter pieces: 全てのピース配列
  /// - Returns: `owner`に紐づくピース配列
  func getOwnedPieces(pieces: [Piece]) -> [Piece] {
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
  func computeCandidateMoves(board: Board, pieces: [Piece]) -> [CandidateMove] {
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
