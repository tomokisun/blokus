#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct BoardView: View {
  @Environment(\.cellSize) var cellSize
  let store: StoreOf<Game>

  public init(store: StoreOf<Game>) {
    self.store = store
  }

  public var body: some View {
    let state = store.gameState
    let highlightCells = store.highlightCells
    let previewCells = previewCellsAt()

    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0..<BoardConstants.boardSize, id: \.self) { y in
        GridRow {
          ForEach(0..<BoardConstants.boardSize, id: \.self) { x in
            let point = BoardPoint(x: x, y: y)
            let owner = state.board[point]
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
              store.send(.boardCellTapped(point))
            }
          }
        }
      }
    }
  }

  private func previewCellsAt() -> Set<BoardPoint> {
    []
  }
}
#endif
