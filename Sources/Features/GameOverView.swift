#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct GameOverView: View {
  let store: StoreOf<Game>

  public init(store: StoreOf<Game>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 20) {
      Text("Game Over")
        .font(.largeTitle)
        .fontWeight(.bold)

      let sortedScores = store.scores.sorted { $0.score > $1.score }

      ForEach(Array(sortedScores.enumerated()), id: \.offset) { index, entry in
        let playerIndex = store.gameState.turnOrder.firstIndex(of: entry.playerId) ?? 0
        HStack {
          Text("#\(index + 1)")
            .font(.title2)
            .fontWeight(.bold)
            .frame(width: 40)
          Circle()
            .fill(PlayerColor.color(for: playerIndex))
            .frame(width: 24, height: 24)
          Text(entry.playerId.displayName)
            .font(.title3)
          Spacer()
          Text("\(entry.score)pt")
            .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .padding(.horizontal)
      }

      Button("New Game") {
        store.send(.newGameButtonTapped)
      }
      .buttonStyle(.borderedProminent)
      .padding(.top)
    }
    .padding()
  }
}
#endif
