import SwiftUI

struct NewGameView: View {
  @Binding var state: GameState
  @State var computerMode = false
  
  init(state: Binding<GameState>) {
    self._state = state
  }

  var body: some View {
    List {
      Toggle("Computer Mode", isOn: $computerMode)

      Button("Start Game") {
        withAnimation(.default) {
          state = .playing(computerMode: computerMode)
        }
      }
    }
  }
}
