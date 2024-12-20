import Foundation

protocol Computer: Actor {
  var owner: Player { get }
  
  init(owner: Player)
  
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
  
  func getPlayerPieces(from pieces: [Piece], owner: Player) -> [Piece] {
    return pieces.filter { $0.owner == owner }
  }
  
  /// ボードから指定プレイヤーのセルを取得します。
  func getPlayerCells(from board: Board, owner: Player) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        if board.cells[x][y].owner == owner {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
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
      // ピースの全オリエンテーションからユニークな形状を取得
      let uniqueOrientations = generateUniqueOrientations(for: piece)
      
      // ユニークな姿勢について配置可能性を探る
      for (rotationCase, flippedCase, shapeCoords) in uniqueOrientations {
        var testPiece = piece
        testPiece.orientation = Orientation(rotation: rotationCase, flipped: flippedCase)
        
        // ボード全域探索
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
    return candidates
  }
  
  /// ピースの全8通り(4回転×flipped有無)の形状を生成し、重複を取り除く。
  /// 返値は (rotation, flipped, shapeCoords) のタプル配列で、
  /// shapeCoordsは正規化した座標セットを元に一意性判定を行う。
  private func generateUniqueOrientations(for piece: Piece) -> [(Rotation, Bool, Set<Coordinate>)] {
    let rotations: [Rotation] = [.none, .ninety, .oneEighty, .twoSeventy]
    let flips: [Bool] = [false, true]
    
    var seenShapes = Set<Set<Coordinate>>()
    var results = [(Rotation, Bool, Set<Coordinate>)]()
    
    for r in rotations {
      for f in flips {
        var testPiece = piece
        testPiece.orientation = Orientation(rotation: r, flipped: f)
        let transformed = testPiece.transformedShape()
        
        // 座標群をSetにし、相対位置が比較可能なように正規化
        let normalized = normalizeShapeCoordinates(transformed)
        if !seenShapes.contains(normalized) {
          seenShapes.insert(normalized)
          results.append((r, f, normalized))
        }
      }
    }
    
    return results
  }
  
  /// 座標群を正規化する関数。
  /// 形状比較のために、最小x,yを0に合わせて平行移動しておく。
  private func normalizeShapeCoordinates(_ coords: [Coordinate]) -> Set<Coordinate> {
    let minX = coords.map(\.x).min() ?? 0
    let minY = coords.map(\.y).min() ?? 0
    let shifted = coords.map { Coordinate(x: $0.x - minX, y: $0.y - minY) }
    return Set(shifted)
  }
}
