import ComposableArchitecture

@Reducer
public struct Root {
  @ObservableState
  public struct State: Equatable {
    public var game: Game.State?
    public var newGame: NewGame.State

    public init(
      game: Game.State? = nil,
      newGame: NewGame.State = NewGame.State()
    ) {
      self.game = game
      self.newGame = newGame
    }
  }

  public enum Action {
    case game(Game.Action)
    case newGame(NewGame.Action)
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    Scope(state: \.newGame, action: \.newGame) {
      NewGame()
    }

    Reduce { state, action in
      switch action {
      case let .newGame(.delegate(.startGame(showHighlight))):
        state.game = Game.State(showHighlight: showHighlight)
        return .none

      case .game(.delegate(.backToMenu)):
        state.game = nil
        return .none

      case .game, .newGame:
        return .none
      }
    }
    .ifLet(\.game, action: \.game) {
      Game()
    }
  }
}
