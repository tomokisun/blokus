import SwiftUI

@main
struct BlokusApp: App {
  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        RootView()
          .persistentSystemOverlays(.hidden)
          .environment(\.cellSize, proxy.size.width / 20)
      }
    }
  }
}

enum GameState: Equatable {
  case newGame
  case playing(computerMode: Bool, computerLevel: ComputerLevel, isHighlight: Bool)
}

enum ComputerLevel: String, CaseIterable {
  case easy
  case normal
}

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

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}

