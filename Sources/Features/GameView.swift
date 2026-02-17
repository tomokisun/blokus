#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct GameView: View {
  @Environment(\.cellSize) var cellSize
  let store: StoreOf<Game>

  public init(store: StoreOf<Game>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 12) {
      if store.isGameOver {
        VStack(spacing: 8) {
          Text("Game Over")
            .font(.headline)
            .fontWeight(.bold)

          let winners = store.winnerPlayerIds
          if winners.count == 1 {
            let winnerIndex = store.gameState.turnOrder.firstIndex(of: winners[0]) ?? 0
            Text("\(winners[0].displayName) wins!")
              .foregroundStyle(PlayerColor.color(for: winnerIndex))
              .font(.title3)
          } else {
            Text("Tied: \(winners.map(\.displayName).joined(separator: ", "))")
              .font(.title3)
          }

          Button("New Game") {
            store.send(.newGameButtonTapped)
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
      }

      BoardView(store: store)

      VStack(spacing: 12) {
        Picker(selection: .constant(store.activePlayerIndex)) {
          ForEach(Array(store.scores.enumerated()), id: \.offset) { index, entry in
            Text("\(entry.playerId.displayName): \(entry.score)pt")
              .tag(index)
          }
        } label: {
          Text("Current Player")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)

        HStack(spacing: 40) {
          Button {
            store.send(.rotateButtonTapped)
          } label: {
            Label("Rotate", systemImage: "rotate.left")
          }
          .disabled(store.selectedPieceId == nil)

          Button("New Game") {
            store.send(.newGameButtonTapped)
          }

          Button {
            store.send(.flipButtonTapped)
          } label: {
            Label("Flip", systemImage: "trapezoid.and.line.vertical")
          }
          .disabled(store.selectedPieceId == nil)
        }
      }

      ScrollView(.vertical) {
        LazyVGrid(
          columns: Array(repeating: GridItem(spacing: 0), count: 3),
          alignment: .center,
          spacing: 0
        ) {
          ForEach(store.remainingPiecesForCurrentPlayer, id: \.id) { piece in
            let variant = piece.variants[
              store.selectedPieceId == piece.id ? store.selectedVariantIndex % piece.variants.count : 0
            ]
            Button {
              store.send(.pieceTapped(piece.id))
            } label: {
              PieceView(
                cellSize: cellSize,
                cells: variant,
                color: PlayerColor.color(for: store.activePlayerIndex)
              )
              .padding()
              .background(
                store.selectedPieceId == piece.id
                  ? PlayerColor.color(for: store.activePlayerIndex).opacity(0.2)
                  : Color.clear
              )
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(store.isGameOver)
          }
        }
        .padding(.horizontal, 20)

        Button {
          store.send(.passButtonTapped)
        } label: {
          Text("Pass")
            .frame(height: cellSize * 3)
            .frame(maxWidth: .infinity)
        }
        .disabled(!store.canPass || store.isGameOver)
        .padding(.horizontal, 20)
      }
      .sensoryFeedback(.impact, trigger: store.selectedPieceId)
      .sensoryFeedback(.impact, trigger: store.activePlayerIndex)
    }
  }
}
#endif
