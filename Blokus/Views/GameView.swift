import ComposableArchitecture
import SwiftUI

struct GameView: View {
  let store: StoreOf<GameFeature>
  @Environment(\.cellSize) var cellSize

  init(
    store: StoreOf<GameFeature>
  ) {
    self.store = store
  }

  var body: some View {
    VStack(spacing: 12) {
      if store.isGameOver {
        VStack(spacing: 8) {
          Text(String(localized: "Game Over"))
            .font(.headline)
            .fontWeight(.bold)

          let winners = store.winnerPlayers
          if winners.count == 1 {
            Text("\(winners[0].localizedName) wins")
              .foregroundStyle(winners[0].color)
              .font(.title3)
          } else {
            Text("\(String(localized: "Tied")): \(winners.map { $0.localizedName }.joined(separator: ", "))")
              .foregroundStyle(.primary)
              .font(.title3)
          }

          Button(String(localized: "New Game")) {
            store.send(.view(.backToMenuTapped))
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
      }

      BoardView(
        store: store.scope(
          state: \.boardFeature,
          action: \.boardFeature
        ),
        interactionMode: .interactive
      )
      .overlay {
        if case let .thinking(computer) = store.thinkingState {
          Color.black.opacity(0.7)
            .overlay {
              Label(
                String(format: String(localized: "%@ is thinking..."), computer.localizedName),
                systemImage: "progress.indicator"
              )
              .foregroundStyle(Color.white)
              .symbolEffect(.variableColor.iterative)
            }
        }
      }

      VStack(spacing: 12) {
        Picker(
          selection: Binding(
            get: { store.player },
            set: { _ in }
          )
        ) {
          ForEach(Player.allCases, id: \.color) { playerColor in
            let point = BoardLogic.score(for: playerColor, in: store.board)
            let text = "\(playerColor.localizedName): \(String(format: String(localized: "%dpt"), point))"
            Text(text)
              .tag(playerColor)
          }
        } label: {
          Text(String(localized: "Current player"))
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .disabled(store.computerMode)

        HStack(spacing: 40) {
          Button {
            store.send(.view(.rotateTapped))
          } label: {
            let flipped = store.pieces.first?.orientation.flipped ?? false
            Label(
              String(localized: "Rotate"),
              systemImage: flipped ? "rotate.right" : "rotate.left"
            )
          }
          .disabled(!store.canUserInteract)

          Button {
            store.send(.view(.replayButtonTapped))
          } label: {
            Text(String(localized: "Replay"))
          }

          Button(String(localized: "New Game")) {
            store.send(.view(.backToMenuTapped))
          }
          .disabled(store.isProcessingTurn)

          Button {
            store.send(.view(.flipTapped))
          } label: {
            Label(String(localized: "Flip"), systemImage: "trapezoid.and.line.vertical")
          }
          .disabled(!store.canUserInteract)
        }
      }

      ScrollView(.vertical) {
        LazyVGrid(
          columns: Array(repeating: GridItem(spacing: 0), count: 3),
          alignment: .center,
          spacing: 0
        ) {
          ForEach(store.playerPieces) { piece in
            Button {
              store.send(.view(.selectPiece(piece)))
            } label: {
              PieceView(cellSize: cellSize, piece: piece)
                .padding()
                .background(
                  piece == store.pieceSelection
                    ? store.player.color.opacity(0.2)
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!store.canUserInteract)
          }
        }
        .padding(.horizontal, 20)

        Button {
          store.send(.view(.passTapped))
        } label: {
          Text(String(localized: "Pass"))
            .frame(height: cellSize * 3)
            .frame(maxWidth: .infinity)
        }
        .disabled(!store.canUserInteract || !store.canCurrentPlayerPass)
        .padding(.horizontal, 20)
      }
      .sensoryFeedback(.impact, trigger: store.pieceSelection)
      .sensoryFeedback(.impact, trigger: store.pieces)
      .sensoryFeedback(.impact, trigger: store.player)
      .sheet(isPresented: Binding(
        get: { store.isReplaySheetPresented },
        set: { isPresented in
          if isPresented {
            store.send(.view(.replayButtonTapped))
          } else {
            store.send(.view(.replaySheetDismissed))
          }
        }
      )) {
        ReplayView(
          store: ComposableArchitecture.Store(
            initialState: ReplayFeature.State(truns: store.replayTruns),
            reducer: {
              ReplayFeature()
            }
          )
        )
      }
    }
  }
}

#Preview("Game - Player Turn") {
  let gameState: GameFeature.State = {
    let playerPiece = Piece.allPieces.first { $0.owner == .red }
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
    state.pieceSelection = playerPiece
    return state
  }()

  return GeometryReader { proxy in
    GameView(
      store: ComposableArchitecture.Store(
        initialState: gameState,
        reducer: {
          GameFeature()
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

#Preview("Game - AI Thinking") {
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
    state.player = .blue
    state.isProcessingTurn = true
    state.thinkingState = .thinking(.blue)
    return state
  }()

  return GeometryReader { proxy in
    GameView(
      store: ComposableArchitecture.Store(
        initialState: gameState,
        reducer: {
          GameFeature()
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

#Preview("Game - Game Over") {
  let gameState: GameFeature.State = {
    var board = Board()
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        board.cells[x][y] = Cell(owner: (x + y).isMultiple(of: 2) ? .red : .blue)
      }
    }

    var state = GameFeature.State(
      isHighlight: true,
      computerMode: true,
      computerLevel: .easy
    )
    state.board = board
    state.boardFeature.board = board
    state.isGameOver = true
    state.consecutivePasses = 2
    state.replayTruns = [
      Trun(index: 0, action: .pass, owner: .red),
      Trun(index: 0, action: .pass, owner: .blue)
    ]
    return state
  }()

  return GeometryReader { proxy in
    GameView(
      store: ComposableArchitecture.Store(
        initialState: gameState,
        reducer: {
          GameFeature()
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
