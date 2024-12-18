import SwiftUI

struct PieceView: View {
  let cellSize: CGFloat
  let piece: Piece
  
  var body: some View {
    let shape = piece.transformedShape()
    
    let minX = shape.map(\.x).min() ?? 0
    let minY = shape.map(\.y).min() ?? 0
    let maxX = shape.map(\.x).max() ?? 0
    let maxY = shape.map(\.y).max() ?? 0
    
    // 左上を(0,0)に揃える正規化
    let normalizedCells = Set(shape.map { Coordinate(x: $0.x - minX, y: $0.y - minY) })
    
    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0...(maxY - minY), id: \.self) { row in
        GridRow {
          ForEach(0...(maxX - minX), id: \.self) { col in
            if normalizedCells.contains(where: { $0.x == col && $0.y == row }) {
              Rectangle()
                .fill(piece.owner.color)
                .frame(width: cellSize, height: cellSize)
                .border(Color.white, width: 1)
            } else {
              Rectangle()
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
            }
          }
        }
      }
    }
    .frame(minWidth: cellSize * 5, minHeight: cellSize * 5)
  }
}
