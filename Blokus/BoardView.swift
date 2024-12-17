import SwiftUI

struct BoardView: View {
  @Environment(\.cellSize) var cellSize

  @Binding var board: Board
  let onTapGesture: (Coordinate) -> Void
  
  var body: some View {
    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0..<board.height, id: \.self) { row in
        GridRow {
          ForEach(0..<board.width, id: \.self) { col in
            let c = Coordinate(x: col, y: row)
            let cell = board.cells[row][col]
            
            // ハイライト判定
            let isHighlighted = board.highlightedCoordinates.contains(c)
            
            Group {
              switch cell {
              case .empty:
                Rectangle()
                  .fill(isHighlighted ? Color.purple.opacity(0.4) : Color.gray.opacity(0.2))
                  .frame(width: cellSize, height: cellSize)
                  .onTapGesture {
                    onTapGesture(c)
                  }

              case let .occupied(_, owner):
                Rectangle()
                  .fill(owner.color)
                  .frame(width: cellSize, height: cellSize)
              }
            }
            .border(Color.black, width: 0.5)
          }
        }
      }
    }
  }
}

