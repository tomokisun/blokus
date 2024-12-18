import SwiftUI

struct NewGameView: View {
  @Binding var state: GameState
  
  @State var isHighlight = true
  @State var computerMode = true
  @State var computerLevel = ComputerLevel.easy
  
  init(state: Binding<GameState>) {
    self._state = state
  }

  var body: some View {
    List {
      Toggle("Show Highlight", isOn: $isHighlight)

      Toggle("Computer Mode", isOn: $computerMode)
      
      if computerMode {
        Picker("Computer Level", selection: $computerLevel) {
          ForEach(ComputerLevel.allCases, id: \.rawValue) { level in
            Text(level.rawValue).tag(level)
          }
        }
      }

      Button("Start Game") {
        withAnimation(.default) {
          state = .playing(
            computerMode: computerMode,
            computerLevel: computerLevel,
            isHighlight: isHighlight
          )
        }
      }
    }
  }
}
