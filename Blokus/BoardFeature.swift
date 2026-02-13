import ComposableArchitecture

@Reducer
struct BoardFeature {
  @ObservableState struct State {
    var board: Board
  }

  enum Action {
    case view(ViewAction)
    case delegate(DelegateAction)

    enum ViewAction: Equatable {
      case boardTapped(Coordinate)
    }

    enum DelegateAction: Equatable {
      case tapped(Coordinate)
    }
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .view(.boardTapped(coordinate)):
        return .send(.delegate(.tapped(coordinate)))
      case .delegate:
        return .none
      }
    }
  }
}
