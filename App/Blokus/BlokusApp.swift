import ComposableArchitecture
import DesignSystem
import Domain
import Features
import SwiftUI

@main
struct BlokusApp: App {
  let store = Store(initialState: Root.State()) {
    Root()
      ._printChanges()
  }

  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        RootView(store: store)
          .environment(\.cellSize, proxy.size.width / CGFloat(BoardConstants.boardSize))
      }
    }
  }
}
