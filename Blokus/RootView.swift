import ComposableArchitecture
import SwiftUI

struct RootView: View {
  let store: StoreOf<RootFeature>

  var body: some View {
    Group {
      if let gameStore = store.scope(state: \.game, action: \.game) {
        GameView(store: gameStore)
      } else {
        NavigationStack {
          NewGameView(store: store)
            .navigationTitle(String(localized: "Blokus App"))
        }
      }
    }
    .sensoryFeedback(.impact, trigger: store.isHighlight)
  }
}

#Preview("Root - New Game") {
  GeometryReader { proxy in
    RootView(
      store: Store(
        initialState: RootFeature.State(),
        reducer: {
          RootFeature()
        },
        withDependencies: {
          $0.aiEngineClient = RandomAIEngineClient()
          $0.auditLogger = LiveAuditLogger()
        }
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}

#Preview("Root - In Game") {
  let gameState: GameFeature.State = {
    var board = Board()
    board.cells[0][0] = Cell(owner: .red)
    board.cells[Board.width - 1][0] = Cell(owner: .blue)

    var state = GameFeature.State(
      isHighlight: true,
      computerMode: true,
      computerLevel: .easy
    )
    state.board = board
    state.boardFeature.board = board
    state.player = .red
    return state
  }()

  var rootState = RootFeature.State()
  rootState.game = gameState

  return GeometryReader { proxy in
    RootView(
      store: Store(
        initialState: rootState,
        reducer: {
          RootFeature()
        },
        withDependencies: {
          $0.aiEngineClient = RandomAIEngineClient()
          $0.auditLogger = LiveAuditLogger()
        }
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}

#Preview("Root - AI Thinking") {
  let gameState: GameFeature.State = {
    var board = Board()
    board.cells[0][0] = Cell(owner: .red)
    board.cells[Board.width - 1][Board.height - 1] = Cell(owner: .blue)

    var state = GameFeature.State(
      isHighlight: true,
      computerMode: true,
      computerLevel: .easy
    )
    state.board = board
    state.boardFeature.board = board
    state.player = .blue
    state.isProcessingTurn = true
    state.thinkingState = .thinking(.blue)
    return state
  }()

  var rootState = RootFeature.State()
  rootState.game = gameState

  return GeometryReader { proxy in
    RootView(
      store: Store(
        initialState: rootState,
        reducer: {
          RootFeature()
        },
        withDependencies: {
          $0.aiEngineClient = RandomAIEngineClient()
          $0.auditLogger = LiveAuditLogger()
        }
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}
