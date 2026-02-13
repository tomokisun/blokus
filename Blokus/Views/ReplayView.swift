import ComposableArchitecture
import SwiftUI

struct ReplayView: View {
  let store: StoreOf<ReplayFeature>

  init(store: StoreOf<ReplayFeature>) {
    self.store = store
  }

  var body: some View {
    VStack(spacing: 20) {
      LazyVGrid(columns: Array(repeating: GridItem(spacing: 0), count: 2), spacing: 0) {
        ForEach(Player.allCases, id: \.color) { playerColor in
          let point = BoardLogic.score(for: playerColor, in: store.board)
          Text(String(format: String(localized: "%dpt"), point))
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(playerColor.color)
            .foregroundStyle(Color.white)
            .font(.system(.headline, design: .rounded, weight: .bold))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal)

      BoardView(
        store: store.scope(
          state: \.replayBoard,
          action: \.board
        ),
        interactionMode: .readOnly
      )

      ProgressView(value: store.progress, total: 1.0)
        .padding(.horizontal)

      HStack {
        Button(store.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
          store.send(.view(.playPauseTapped))
        }

        Button(String(localized: "Stop")) {
          store.send(.view(.stopTapped))
        }
      }

      Picker(String(format: String(localized: "Speed: %.1fx"), store.speed), selection: Binding(
        get: { store.speed },
        set: { store.send(.view(.speedChanged($0))) }
      )) {
        Text(String(format: String(localized: "%.1fx"), 0.5)).tag(0.5)
        Text(String(format: String(localized: "%.1fx"), 1.0)).tag(1.0)
        Text(String(format: String(localized: "%.1fx"), 1.5)).tag(1.5)
        Text(String(format: String(localized: "%.1fx"), 2.0)).tag(2.0)
        Text(String(format: String(localized: "%.1fx"), 3.0)).tag(3.0)
        Text(String(format: String(localized: "%.1fx"), 5.0)).tag(5.0)
      }
    }
    .onDisappear {
      store.send(.view(.disappear))
    }
  }
}

#Preview("Replay - Empty") {
  GeometryReader { proxy in
    ReplayView(
      store: ComposableArchitecture.Store(
        initialState: ReplayFeature.State(truns: []),
        reducer: {
          ReplayFeature()
        },
        withDependencies: {
          $0.auditLogger = LiveAuditLogger()
        }
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}

#Preview("Replay - With Progress") {
  let initialState: ReplayFeature.State = {
    let redPiece = Piece.allPieces.first { $0.owner == .red }!
    let bluePiece = Piece.allPieces.first { $0.owner == .blue }!
    let truns: [Trun] = [
      Trun(index: 0, action: .place(piece: redPiece, at: .init(x: 0, y: 0)), owner: .red),
      Trun(index: 0, action: .place(piece: bluePiece, at: .init(x: 19, y: 0)), owner: .blue),
      Trun(index: 1, action: .pass, owner: .red),
    ]

    var state = ReplayFeature.State(truns: truns)
    state.currentIndex = 2

    var board = Board()
    for trun in truns.prefix(state.currentIndex) {
      if case let .place(piece, origin) = trun.action {
        if let updated = try? BoardLogic.placePiece(piece: piece, at: origin, in: board) {
          board = updated
        }
      }
    }
    state.replayBoard.board = board
    state.speed = 2.0
    return state
  }()

  return GeometryReader { proxy in
    ReplayView(
      store: ComposableArchitecture.Store(
        initialState: initialState,
        reducer: {
          ReplayFeature()
        },
        withDependencies: {
          $0.auditLogger = LiveAuditLogger()
        }
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}
