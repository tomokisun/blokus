import Foundation

struct ComputerPlayer {
  let owner: PlayerColor
  let level: ComputerLevel
  
  // CPUが1手実行するロジック例
  // - 手番が来たらBoardとpiecesを参照
  // - piecesからおける場所を探して1手指す
  mutating func performCPUMove(board: inout Board, pieces: inout [Piece]) {
    // CPUが持っているピースを抽出し、いったんシャッフルする
    var cpuPieces = pieces
        .filter { $0.owner == owner }
        .shuffled()
    
    if level == .normal {
      // baseShape.countをキーにしてグルーピングし、各グループ内もシャッフルする
      let groupedByCount = Dictionary(grouping: cpuPieces, by: { $0.baseShape.count })
          // mapValuesを用いて、各[Piece]をシャッフル
          .mapValues { $0.shuffled() }

      // countの値が大きい順に並べた上で、各グループを平坦化([Piece])へ
      cpuPieces = groupedByCount
          .sorted { $0.key > $1.key }
          .flatMap(\.value)
    }
    
    // ピースがなければパス
    guard !cpuPieces.isEmpty else {
      print("CPU(\(owner)) has no pieces left and passes.")
      return
    }
    
    // 超簡易的な戦略:
    // 1. ピースを1つずつ試す
    for piece in cpuPieces {
      // ピースの全オリエンテーションを試す（回転4種 x flipped有無の2倍 = 8通り）
      for rotationCase in [Rotation.none, .ninety, .oneEighty, .twoSeventy] {
        for flippedCase in [false, true] {
          var testPiece = piece
          testPiece.orientation = Orientation(rotation: rotationCase, flipped: flippedCase)
          
          // ボード上の全マスを起点におけるか調べる
          for y in 0..<board.height {
            for x in 0..<board.width {
              let origin = Coordinate(x: x, y: y)
              if board.canPlacePiece(piece: testPiece, at: origin) {
                // 配置可能な場所が見つかったので配置
                do {
                  try board.placePiece(piece: testPiece, at: origin)
                  // 配置したピースをpiecesから削除
                  if let idx = pieces.firstIndex(where: { $0.id == piece.id }) {
                    pieces.remove(at: idx)
                  }
                  print("CPU(\(owner)) placed piece \(piece.id) at (\(x), \(y))")
                  return // 1手指したら終了
                } catch {
                  // 理論上canPlacePieceでOK判定後なら起きないはず
                  continue
                }
              }
            }
          }
        }
      }
    }
    
    // ここまできたら配置できるピースがない=パス
    print("CPU(\(owner)) cannot place any piece and passes.")
  }
}
