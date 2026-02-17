#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import ComposableArchitecture
import SwiftUI

public struct NewGameView: View {
  @Bindable var store: StoreOf<NewGame>

  public init(store: StoreOf<NewGame>) {
    self.store = store
  }

  public var body: some View {
    List {
      Toggle("Show Highlight", isOn: $store.showHighlight)

      Button("Start Game") {
        store.send(.startGameButtonTapped)
      }
    }
  }
}
#endif
