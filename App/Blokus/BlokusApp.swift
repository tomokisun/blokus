import SwiftUI
import Domain
import DesignSystem
import Features

@main
struct BlokusApp: App {
  @State private var viewModel = GameViewModel()

  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        RootView(viewModel: viewModel)
          .environment(\.cellSize, proxy.size.width / CGFloat(BoardConstants.boardSize))
      }
    }
  }
}
