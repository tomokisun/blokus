import ComposableArchitecture

@Reducer
struct RootFeature {
  @ObservableState struct State {
    var isHighlight = true
    var computerMode = true
    var computerLevel: ComputerLevel = .easy
    var game: GameFeature.State?
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case startGameButtonTapped
    case game(GameFeature.Action)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case .startGameButtonTapped:
        state.game = GameFeature.State(
          isHighlight: state.isHighlight,
          computerMode: state.computerMode,
          computerLevel: state.computerLevel
        )
        return .none

      case .game(.view(.backToMenuTapped)):
        state.game = nil
        return .none

      case .game:
        return .none

      case .binding:
        return .none
      }
    }
    .ifLet(\.game, action: \.game) {
      GameFeature()
    }
  }
}
