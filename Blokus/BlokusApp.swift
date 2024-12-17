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

enum GameState {
  case newGame
  case playing(computerMode: Bool)
}

struct RootView: View {
  @State var state = GameState.newGame
  @State var computerMode = false
  
  var body: some View {
    switch state {
    case .newGame:
      NewGameView(state: $state)

    case let .playing(computerMode):
      ContentView(computerMode: computerMode)
    }
  }
}

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}

