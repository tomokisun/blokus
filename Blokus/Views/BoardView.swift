import ComposableArchitecture
import SwiftUI

struct BoardView: View {
  @Environment(\.cellSize) var cellSize

  let store: StoreOf<BoardFeature>
  enum InteractionMode: Equatable {
    case interactive
    case readOnly
  }

  let interactionMode: InteractionMode
  
  var body: some View {
    let isInteractive = interactionMode == .interactive

    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
      ForEach(0..<Board.height, id: \.self) { y in
        GridRow {
        ForEach(0..<Board.width, id: \.self) { x in
            let c = Coordinate(x: x, y: y)
            let isHighlighted = store.board.highlightedCoordinates.contains(c)
            let cell = store.board.cells[x][y]
            
            Group {
              if let owner = cell.owner {
                Rectangle()
                  .fill(owner.color)
                  .frame(width: cellSize, height: cellSize)
              } else {
                let isPreview = store.board.previewCoordinates.contains(c)
                Rectangle()
                  .fill(
                    isPreview ? Color.green.opacity(0.5) :
                    isHighlighted ? Color.purple.opacity(0.4) :
                    Color.gray.opacity(0.2)
                  )
                  .frame(width: cellSize, height: cellSize)
              }
            }
            .contentShape(Rectangle())
            .border(Color.black, width: 0.5)
            .accessibilityElement()
            .accessibilityLabel(
              boardCellLabel(x: c.x, y: c.y, owner: cell.owner, highlighted: isHighlighted)
            )
            .accessibilityHint(
              isInteractive
                ? String(localized: "Double-tap to place here")
                : String(localized: "Replay board is read-only")
            )
            .accessibilityValue(
              boardCellValue(owner: cell.owner, highlighted: isHighlighted)
            )
            .accessibilityAddTraits(isInteractive ? .isButton : .isImage)
            .onTapGesture {
              guard isInteractive else { return }
              store.send(.view(.boardTapped(c)))
            }
            .allowsHitTesting(isInteractive)
          }
        }
      }
    }
  }

  init(
    board: Board,
    interactionMode: InteractionMode
  ) {
    self.store = ComposableArchitecture.Store(
      initialState: BoardFeature.State(board: board),
      reducer: {
        BoardFeature()
      }
    )
    self.interactionMode = interactionMode
  }

  init(
    store: StoreOf<BoardFeature>,
    interactionMode: InteractionMode
  ) {
    self.store = store
    self.interactionMode = interactionMode
  }

  private func boardCellLabel(
    x: Int,
    y: Int,
    owner: Player?,
    highlighted: Bool
  ) -> String {
    let stateText: String
    if let owner {
      stateText = String(format: String(localized: "%@'s piece"), owner.localizedName)
    } else if highlighted {
      stateText = String(localized: "Highlighted")
    } else {
      stateText = String(localized: "Empty")
    }
    return "\(stateText) (x: \(x), y: \(y))"
  }

  private func boardCellValue(owner: Player?, highlighted: Bool) -> String {
    if let owner {
      return String(format: String(localized: "%@ piece"), owner.localizedName)
    } else if highlighted {
      return String(localized: "Possible placement")
    }
    return String(localized: "Not occupied")
  }
}
