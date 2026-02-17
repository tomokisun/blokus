import ComposableArchitecture

@Reducer
public struct NewGame {
  @ObservableState
  public struct State: Equatable {
    public var showHighlight: Bool

    public init(showHighlight: Bool = true) {
      self.showHighlight = showHighlight
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case startGameButtonTapped
    case delegate(Delegate)

    public enum Delegate {
      case startGame(showHighlight: Bool)
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
        return .send(.delegate(.startGame(showHighlight: state.showHighlight)))

      case .delegate:
        return .none
      }
    }
  }
}
