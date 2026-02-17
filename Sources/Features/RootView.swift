#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import ComposableArchitecture
import SwiftUI

public struct RootView: View {
  let store: StoreOf<Root>

  public init(store: StoreOf<Root>) {
    self.store = store
  }

  public var body: some View {
    Group {
      if let gameStore = store.scope(state: \.game, action: \.game) {
        GameView(store: gameStore)
      } else {
        NavigationStack {
          NewGameView(store: store.scope(state: \.newGame, action: \.newGame))
            .navigationTitle("Blokus")
        }
      }
    }
  }
}
#endif
