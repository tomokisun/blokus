import ComposableArchitecture

@Reducer
public struct NewGame {
  @ObservableState
  public struct State: Equatable {
    public var showHighlight: Bool
    public var aiPlayerCount: Int

    public init(showHighlight: Bool = true, aiPlayerCount: Int = 3) {
      self.showHighlight = showHighlight
      self.aiPlayerCount = aiPlayerCount
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case startGameButtonTapped
    case delegate(Delegate)

    public enum Delegate {
      case startGame(showHighlight: Bool, aiPlayerCount: Int)
    }
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .startGameButtonTapped:
        return .send(.delegate(.startGame(
          showHighlight: state.showHighlight,
          aiPlayerCount: state.aiPlayerCount
        )))

      case .delegate:
        return .none
      }
    }
  }
}
