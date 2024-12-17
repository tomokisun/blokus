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
  case playing(computerMode: Bool, computerLevel: ComputerLevel, isHighlight: Bool)
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
      NavigationStack {
        NewGameView(state: $state)
          .navigationTitle(Text("Blokus App"))
      }

    case let .playing(computerMode, level, isHighlight):
      ContentView(isHighlight: isHighlight, computerMode: computerMode, computerLevel: level)
    }
  }
}

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}

