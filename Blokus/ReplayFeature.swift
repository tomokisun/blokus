import ComposableArchitecture
import Foundation

@Reducer
struct ReplayFeature {
  @ObservableState struct State {
    var board = Board()
    var replayBoard: BoardFeature.State
    let truns: [Trun]
    var currentIndex: Int = 0
    var isPaused: Bool = true
    var speed: Double = 1.0

    init(truns: [Trun]) {
      let orderedTruns = truns.sorted(by: { $0.index < $1.index })
      self.truns = orderedTruns
      self.replayBoard = BoardFeature.State(board: Board())
    }

    var isPlaying: Bool {
      currentIndex < truns.count && !isPaused
    }

    var progress: Double {
      guard !truns.isEmpty else { return 0.0 }
      return Double(currentIndex) / Double(truns.count)
    }
  }

  enum Action {
    case board(BoardFeature.Action)
    case view(ViewAction)

    enum ViewAction: Equatable {
      case playPauseTapped
      case stopTapped
      case speedChanged(Double)
      case tick
      case disappear
    }
  }

  enum CancelID {
    case playback
  }

  @Dependency(\.continuousClock) var clock

  var body: some Reducer<State, Action> {
    Scope(state: \.replayBoard, action: \.board) {
      BoardFeature()
    }

    Reduce { state, action in
      switch action {
      case let .board(.delegate(.tapped(coordinate))):
        _ = coordinate
        return .none

      case .board:
        return .none

      case .view(.playPauseTapped):
        if state.currentIndex >= state.truns.count {
          state.currentIndex = 0
          state.board = Board()
          state.replayBoard.board = state.board
        }

        if state.isPlaying {
          state.isPaused = true
          return .cancel(id: CancelID.playback)
        }

        state.isPaused = false
        return .run { [speed = state.speed] send in
          while true {
            let interval = max(0.1, 1.0 / max(0.1, speed))
            try await clock.sleep(for: .seconds(interval))
            await send(.view(.tick))
          }
        }
        .cancellable(id: CancelID.playback)

      case .view(.stopTapped):
        state.currentIndex = 0
        state.isPaused = true
        state.board = Board()
        state.replayBoard.board = state.board
        return .cancel(id: CancelID.playback)

      case let .view(.speedChanged(speed)):
        state.speed = speed
        return .none

      case .view(.tick):
        guard !state.isPaused else {
          return .cancel(id: CancelID.playback)
        }

        guard state.currentIndex < state.truns.count else {
          state.isPaused = true
          return .cancel(id: CancelID.playback)
        }

        let trun = state.truns[state.currentIndex]
        switch trun.action {
        case let .place(piece, origin):
          do {
            state.board = try BoardLogic.placePiece(piece: piece, at: origin, in: state.board)
          } catch {
            state.isPaused = true
            return .cancel(id: CancelID.playback)
          }
        case .pass:
          break
        }

        state.replayBoard.board = state.board
        state.currentIndex += 1

        if state.currentIndex >= state.truns.count {
          state.isPaused = true
          return .cancel(id: CancelID.playback)
        }
        return .none

      case .view(.disappear):
        state.isPaused = true
        return .cancel(id: CancelID.playback)
      }
    }
  }
}
