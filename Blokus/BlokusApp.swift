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
  case playing(computerMode: Bool, computerLevel: ComputerLevel)
}

enum ComputerLevel: String, CaseIterable {
  case easy
  case normal
}

struct RootView: View {
  @State var state = GameState.newGame
  
  var body: some View {
    switch state {
    case .newGame:
      NewGameView(state: $state)

    case let .playing(computerMode, level):
      ContentView(computerMode: computerMode, computerLevel: level)
    }
  }
}

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}

