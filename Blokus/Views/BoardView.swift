import SwiftUI

struct BoardView: View {
  @Environment(\.cellSize) var cellSize

  @Binding var board: Board
  let onTapGesture: (Coordinate) -> Void
  
  var body: some View {
    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0..<Board.width, id: \.self) { row in
        GridRow {
          ForEach(0..<Board.height, id: \.self) { column in
            let c = Coordinate(x: column, y: row)
            let isHighlighted = board.highlightedCoordinates.contains(c)
            let cell = board.cells[row][column]
            
            Group {
              if let owner = cell.owner {
                Rectangle()
                  .fill(owner.color)
                  .frame(width: cellSize, height: cellSize)
              } else {
                Rectangle()
                  .fill(isHighlighted ? Color.purple.opacity(0.4) : Color.gray.opacity(0.2))
                  .frame(width: cellSize, height: cellSize)
              }
            }
            .border(Color.black, width: 0.5)
            .onTapGesture {
              onTapGesture(c)
            }
          }
        }
      }
    }
  }
}

