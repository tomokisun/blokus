#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain
import DesignSystem

public struct GameView: View {
  @Environment(\.cellSize) var cellSize
  let viewModel: GameViewModel

  public init(viewModel: GameViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 12) {
      // Game Over banner
      if viewModel.isGameOver {
        VStack(spacing: 8) {
          Text("Game Over")
            .font(.headline)
            .fontWeight(.bold)

          let winners = viewModel.winnerPlayerIds
          if winners.count == 1 {
            let winnerIndex = viewModel.currentState.turnOrder.firstIndex(of: winners[0]) ?? 0
            Text("\(winners[0].displayName) wins!")
              .foregroundStyle(PlayerColor.color(for: winnerIndex))
              .font(.title3)
          } else {
            Text("Tied: \(winners.map(\.displayName).joined(separator: ", "))")
              .font(.title3)
          }

          Button("New Game") {
            viewModel.backToMenu()
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
      }

      // Board
      BoardView(viewModel: viewModel)

      VStack(spacing: 12) {
        // Player score picker (read-only segmented display)
        Picker(selection: .constant(viewModel.activePlayerIndex)) {
          ForEach(Array(viewModel.scores.enumerated()), id: \.offset) { index, entry in
            Text("\(entry.playerId.displayName): \(entry.score)pt")
              .tag(index)
          }
        } label: {
          Text("Current Player")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)

        // Control buttons
        HStack(spacing: 40) {
          Button {
            viewModel.rotatePiece()
          } label: {
            Label("Rotate", systemImage: "rotate.left")
          }
          .disabled(viewModel.selectedPieceId == nil)

          Button("New Game") {
            viewModel.backToMenu()
          }

          Button {
            viewModel.flipPiece()
          } label: {
            Label("Flip", systemImage: "trapezoid.and.line.vertical")
          }
          .disabled(viewModel.selectedPieceId == nil)
        }
      }

      // Piece selection
      ScrollView(.vertical) {
        LazyVGrid(
          columns: Array(repeating: GridItem(spacing: 0), count: 3),
          alignment: .center,
          spacing: 0
        ) {
          ForEach(viewModel.remainingPiecesForCurrentPlayer, id: \.id) { piece in
            let variant = piece.variants[
              viewModel.selectedPieceId == piece.id ? viewModel.selectedVariantIndex % piece.variants.count : 0
            ]
            Button {
              viewModel.selectPiece(piece.id)
            } label: {
              PieceView(
                cellSize: cellSize,
                cells: variant,
                color: PlayerColor.color(for: viewModel.activePlayerIndex)
              )
              .padding()
              .background(
                viewModel.selectedPieceId == piece.id
                  ? PlayerColor.color(for: viewModel.activePlayerIndex).opacity(0.2)
                  : Color.clear
              )
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isGameOver)
          }
        }
        .padding(.horizontal, 20)

        // Pass button
        Button {
          viewModel.pass()
        } label: {
          Text("Pass")
            .frame(height: cellSize * 3)
            .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canPass || viewModel.isGameOver)
        .padding(.horizontal, 20)
      }
      .sensoryFeedback(.impact, trigger: viewModel.selectedPieceId)
      .sensoryFeedback(.impact, trigger: viewModel.activePlayerIndex)
    }
  }
}
#endif
