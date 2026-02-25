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
      Section {
        Picker("AI Players", selection: $store.aiPlayerCount) {
          Text("0 (All Human)").tag(0)
          Text("1").tag(1)
          Text("2").tag(2)
          Text("3 (Solo vs AI)").tag(3)
        }
      } header: {
        Text("AI Players")
      }

      Section {
        Toggle("Show Highlight", isOn: $store.showHighlight)
      }

      Button("Start Game") {
        store.send(.startGameButtonTapped)
      }
    }
  }
}
#endif
