#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI

public struct RootView: View {
  let viewModel: GameViewModel

  public init(viewModel: GameViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    Group {
      if viewModel.isGameStarted {
        GameView(viewModel: viewModel)
      } else {
        NavigationStack {
          NewGameView(viewModel: viewModel)
            .navigationTitle("Blokus")
        }
      }
    }
  }
}
#endif
