#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain
import DesignSystem

public struct BoardView: View {
  @Environment(\.cellSize) var cellSize
  let viewModel: GameViewModel

  public init(viewModel: GameViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    let state = viewModel.currentState
    let highlightCells = viewModel.highlightCells
    let previewCells = previewCellsAt(viewModel: viewModel)

    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0..<20, id: \.self) { y in
        GridRow {
          ForEach(0..<20, id: \.self) { x in
            let point = BoardPoint(x: x, y: y)
            let boardIndex = y * 20 + x
            let owner = state.board[boardIndex]
            let isPreview = previewCells.contains(point)
            let isHighlight = highlightCells.contains(point)

            Group {
              if let owner {
                Rectangle()
                  .fill(PlayerColor.color(for: owner, in: state))
              } else if isPreview {
                Rectangle()
                  .fill(Color.green.opacity(0.5))
              } else if isHighlight {
                Rectangle()
                  .fill(Color.purple.opacity(0.4))
              } else {
                Rectangle()
                  .fill(Color.gray.opacity(0.2))
              }
            }
            .frame(width: cellSize, height: cellSize)
            .border(Color.black, width: 0.5)
            .contentShape(Rectangle())
            .onTapGesture {
              guard !viewModel.isGameOver else { return }
              viewModel.tapBoard(at: point)
            }
          }
        }
      }
    }
  }

  private func previewCellsAt(viewModel: GameViewModel) -> Set<BoardPoint> {
    // Show preview of where the piece would land when hovering over a highlight cell
    // For now, no live preview - just show highlights
    return []
  }
}
#endif
