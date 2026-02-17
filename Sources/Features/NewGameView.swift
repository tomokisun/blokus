#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI

public struct NewGameView: View {
  let viewModel: GameViewModel

  public init(viewModel: GameViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    List {
      Toggle("Show Highlight", isOn: Binding(
        get: { viewModel.showHighlight },
        set: { viewModel.showHighlight = $0 }
      ))

      Button("Start Game") {
        viewModel.startGame(showHighlight: viewModel.showHighlight)
      }
    }
  }
}
#endif
