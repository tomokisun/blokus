#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain

public struct PieceView: View {
  public let cellSize: CGFloat
  public let cells: [BoardPoint]
  public let color: Color

  public init(cellSize: CGFloat, cells: [BoardPoint], color: Color) {
    self.cellSize = cellSize
    self.cells = cells
    self.color = color
  }

  public var body: some View {
    let minX = cells.map(\.x).min() ?? 0
    let minY = cells.map(\.y).min() ?? 0
    let maxX = cells.map(\.x).max() ?? 0
    let maxY = cells.map(\.y).max() ?? 0
    let normalizedCells = Set(cells.map { BoardPoint(x: $0.x - minX, y: $0.y - minY) })

    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0...(max(maxY - minY, 0)), id: \.self) { row in
        GridRow {
          ForEach(0...(max(maxX - minX, 0)), id: \.self) { col in
            if normalizedCells.contains(BoardPoint(x: col, y: row)) {
              Rectangle()
                .fill(color)
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
#endif
