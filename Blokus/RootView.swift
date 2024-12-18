import SwiftUI

struct RootView: View {
  @State var state = GameState.newGame
  
  var body: some View {
    Group {
      switch state {
      case .newGame:
        NavigationStack {
          NewGameView(state: $state)
            .navigationTitle(Text("Blokus App"))
        }
        
      case let .playing(computerMode, computerLevel, isHighlight):
        GameView(
          store: Store(
            isHighlight: isHighlight,
            computerMode: computerMode,
            computerLevel: computerLevel
          )
        )
      }
    }
    .sensoryFeedback(.impact, trigger: state)
  }
}
