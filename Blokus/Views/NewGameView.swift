import SwiftUI
import ComposableArchitecture

struct NewGameView: View {
  @Bindable var store: StoreOf<RootFeature>

  var body: some View {
    List {
      Toggle(String(localized: "Show Highlight"), isOn: $store.isHighlight)

      Toggle(String(localized: "Computer Mode"), isOn: $store.computerMode)

      Button(String(localized: "Start Game")) {
        store.send(.startGameButtonTapped)
      }
    }
  }
}
