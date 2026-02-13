import ComposableArchitecture
import Dependencies
import Foundation

// MARK: - Game Feature

@Reducer
struct GameFeature {
  @ObservableState struct State {
    let isHighlight: Bool
    let computerMode: Bool
    let computerLevel: ComputerLevel
    var board: Board = Board()
    var boardFeature: BoardFeature.State
    var pieces: [Piece] = Piece.allPieces
    var player: Player = .red
    var pieceSelection: Piece?
    var thinkingState: ComputerThinkingState = .idle
    var isProcessingTurn: Bool = false
    var consecutivePasses: Int = 0
    var isGameOver: Bool = false
    var replayTruns: [Trun] = []
    var turnIndex: Int = 0
    var revision: Int = 0
    var turnCoordinator: TurnCoordinator.State = .init()
    var isReplaySheetPresented = false
    var placementCandidateOrigin: Coordinate?

    init(
      isHighlight: Bool,
      computerMode: Bool,
      computerLevel: ComputerLevel
    ) {
      self.isHighlight = isHighlight
      self.computerMode = computerMode
      self.computerLevel = computerLevel
      let initialBoard = Board()
      self.board = initialBoard
      self.boardFeature = BoardFeature.State(board: initialBoard)
      self.turnCoordinator = TurnCoordinator.State()
    }

    var playerPieces: [Piece] {
      pieces.filter { $0.owner == player }
    }

    var canCurrentPlayerPass: Bool {
      guard !isGameOver else { return false }
      return !BoardLogic.hasPlaceableMove(for: player, pieces: pieces, in: board)
    }

    var winnerPlayers: [Player] {
      let scores = Player.allCases.map { ($0, BoardLogic.score(for: $0, in: board)) }
      guard let maxScore = scores.map(\.1).max() else { return [] }
      return scores.filter { $0.1 == maxScore }.map(\.0)
    }

    var canUserInteract: Bool {
      guard !isGameOver else { return false }
      guard !isProcessingTurn else { return false }
      guard case .idle = thinkingState else { return false }
      if computerMode {
        return player == .red
      }
      return true
    }

    var readOnlySnapshot: ReadOnlyGameStateSnapshot {
      .init(
        board: board,
        pieces: pieces,
        player: player,
        turnIndex: turnIndex,
        revision: revision,
        consecutivePasses: consecutivePasses,
        isGameOver: isGameOver,
        isHighlight: isHighlight,
        computerMode: computerMode,
        computerLevel: computerLevel
      )
    }
  }

  enum Action {
    case view(ViewAction)
    case turnCoordinator(TurnCoordinator.Action)
    case boardFeature(BoardFeature.Action)

    enum ViewAction: Equatable {
      case boardTapped(Coordinate)
      case rotateTapped
      case flipTapped
      case selectPiece(Piece)
      case passTapped
      case backToMenuTapped
      case replayButtonTapped
      case replaySheetDismissed
    }
  }

  @Dependency(\.auditLogger) var auditLogger

  var body: some Reducer<State, Action> {
    Scope(state: \.turnCoordinator, action: \.turnCoordinator) {
      TurnCoordinator()
    }
    Scope(state: \.boardFeature, action: \.boardFeature) {
      BoardFeature()
    }

    Reduce { state, action in
      switch action {
      case let .boardFeature(boardAction):
        switch boardAction {
        case let .delegate(.tapped(coordinate)):
          return reduce(.boardTapped(coordinate), into: &state)
        case .view, .delegate:
          return .none
        }

      case .view(let viewAction):
        return reduce(viewAction, into: &state)

      case let .turnCoordinator(.receiveAIResult(_, requestId)):
        guard let result = TurnCoordinator().consumeResult(for: requestId, in: &state.turnCoordinator) else {
          logDiscarded(
            reason: "stale_result",
            requestId: requestId
          )
          return .none
        }

        switch result {
        case .place(let piece, let origin):
          return placePieceFromAIMove(
            piece: piece,
            coordinate: origin,
            fromAI: true,
            in: &state
          )
        case .pass:
          return registerAIReturnPass(in: &state)
        }

      case .turnCoordinator(.cancelInFlight):
        state.isProcessingTurn = false
        state.thinkingState = .idle
        return .none

      case .turnCoordinator(.launchIfNeeded):
        return .none
      }
    }
  }

  private func logDiscarded(
    reason: String,
    requestId: UUID
  ) {
    auditLogger.log(
      AuditEvent(
        correlationId: requestId.uuidString,
        level: .debug,
        name: "ai.discarded",
        payload: "\(reason) request=\(requestId)",
        timestamp: Date()
      )
    )
  }

  private func reduce(_ action: Action.ViewAction, into state: inout State) -> Effect<Action> {
    switch action {
    case .boardTapped(let coordinate):
      guard state.canUserInteract else { return .none }
      guard let piece = state.pieceSelection else { return .none }

      // If in candidate preview mode and tapped on preview -> confirm placement
      if let candidateOrigin = state.placementCandidateOrigin {
        let previewCoords = BoardLogic.computeFinalCoordinates(for: piece, at: candidateOrigin)
        if previewCoords.contains(coordinate) {
          state.placementCandidateOrigin = nil
          state.board.previewCoordinates.removeAll()
          state.boardFeature.board = state.board
          return placePiece(piece: piece, at: candidateOrigin, fromAI: false, in: &state)
        }
      }

      // Find nearest valid placements
      let candidates = BoardLogic.findNearestValidOrigins(for: piece, near: coordinate, in: state.board)

      if candidates.isEmpty {
        state.placementCandidateOrigin = nil
        state.board.previewCoordinates.removeAll()
        state.boardFeature.board = state.board
        return .none
      }

      if candidates.count == 1 {
        state.placementCandidateOrigin = nil
        state.board.previewCoordinates.removeAll()
        state.boardFeature.board = state.board
        return placePiece(piece: piece, at: candidates[0], fromAI: false, in: &state)
      }

      // Multiple candidates -> show preview of first
      state.placementCandidateOrigin = candidates[0]
      let previewCoords = BoardLogic.computeFinalCoordinates(for: piece, at: candidates[0])
      state.board.previewCoordinates = Set(previewCoords)
      state.boardFeature.board = state.board
      return .none

    case .rotateTapped:
      guard state.canUserInteract else { return .none }
      for index in state.pieces.indices {
        state.pieces[index].orientation.rotate90()
      }
      if let selected = state.pieceSelection,
         let selectedIndex = state.pieces.firstIndex(where: { $0.id == selected.id }) {
        state.pieceSelection = state.pieces[selectedIndex]
      }
      state.placementCandidateOrigin = nil
      state.board.previewCoordinates.removeAll()
      updateHighlights(into: &state)
      return .none

    case .flipTapped:
      guard state.canUserInteract else { return .none }
      for index in state.pieces.indices {
        state.pieces[index].orientation.flip()
      }
      if let selected = state.pieceSelection,
         let selectedIndex = state.pieces.firstIndex(where: { $0.id == selected.id }) {
        state.pieceSelection = state.pieces[selectedIndex]
      }
      state.placementCandidateOrigin = nil
      state.board.previewCoordinates.removeAll()
      updateHighlights(into: &state)
      return .none

    case .selectPiece(let piece):
      guard state.canUserInteract else { return .none }
      guard piece.owner == state.player else { return .none }

      if state.pieceSelection?.id == piece.id {
        state.pieceSelection = nil
      } else {
        state.pieceSelection = state.pieces.first(where: { $0.id == piece.id })
      }

      state.placementCandidateOrigin = nil
      state.board.previewCoordinates.removeAll()
      updateHighlights(into: &state)
      return .none

    case .passTapped:
      guard state.canUserInteract else { return .none }
      guard state.canCurrentPlayerPass else { return .none }
      state.placementCandidateOrigin = nil
      state.board.previewCoordinates.removeAll()
      appendReplay(owner: state.player, action: .pass, in: &state)
      return finishTurn(didPlacePiece: false, in: &state)

    case .backToMenuTapped:
      return .none

    case .replayButtonTapped:
      state.isReplaySheetPresented = true
      return .none

    case .replaySheetDismissed:
      state.isReplaySheetPresented = false
      return .none
    }
  }

  private func placePieceFromAIMove(
    piece: Piece,
    coordinate: Coordinate,
    fromAI: Bool,
    in state: inout State
  ) -> Effect<Action> {
    guard let pieceIndex = state.pieces.firstIndex(where: { $0.id == piece.id }) else {
      return handleAIFailure(in: &state)
    }
    var candidatePiece = state.pieces[pieceIndex]
    candidatePiece.orientation = piece.orientation
    return placePiece(
      piece: candidatePiece,
      at: coordinate,
      fromAI: true,
      in: &state
    )
  }

  private func registerAIReturnPass(in state: inout State) -> Effect<Action> {
    appendReplay(owner: state.player, action: .pass, in: &state)
    return finishTurn(didPlacePiece: false, in: &state)
  }

  private func placePiece(
    piece: Piece,
    at coordinate: Coordinate,
    fromAI: Bool,
    in state: inout State
  ) -> Effect<Action> {
    do {
      let board = try BoardLogic.placePiece(piece: piece, at: coordinate, in: state.board)
      state.board = board
      state.boardFeature.board = board
      if let pieceIndex = state.pieces.firstIndex(where: { $0.id == piece.id }) {
        state.pieces.remove(at: pieceIndex)
      }
      state.revision += 1
      appendReplay(owner: state.player, action: .place(piece: piece, at: coordinate), in: &state)
      state.pieceSelection = nil
      state.board.highlightedCoordinates.removeAll()
      state.board.previewCoordinates.removeAll()
      state.boardFeature.board = state.board
      return finishTurn(didPlacePiece: true, in: &state)
    } catch {
      if fromAI {
        return handleAIFailure(in: &state)
      }
      return .none
    }
  }

  private func finishTurn(didPlacePiece: Bool, in state: inout State) -> Effect<Action> {
    if didPlacePiece {
      state.consecutivePasses = 0
    } else {
      state.consecutivePasses += 1
    }

    if state.consecutivePasses >= Player.allCases.count {
      state.isGameOver = true
      state.thinkingState = .idle
      state.isProcessingTurn = false
      return .none
    }

    advanceTurn(in: &state)

    if state.isGameOver {
      state.thinkingState = .idle
      state.isProcessingTurn = false
      return .none
    }

    if state.computerMode && state.player != .red {
      state.thinkingState = .thinking(state.player)
      state.isProcessingTurn = true
      let snapshot = state.readOnlySnapshot
      state.turnCoordinator.pendingSnapshot = snapshot
      updateHighlights(into: &state)
      return .send(.turnCoordinator(.launchIfNeeded))
    }

    updateHighlights(into: &state)
    state.thinkingState = .idle
    state.isProcessingTurn = false
    return .none
  }

  private func advanceTurn(in state: inout State) {
    state.turnIndex += 1
    if let index = Player.allCases.firstIndex(of: state.player) {
      state.player = Player.allCases[(index + 1) % Player.allCases.count]
    } else {
      state.player = .red
    }
  }

  private func handleAIFailure(in state: inout State) -> Effect<Action> {
    state.thinkingState = .idle
    state.isProcessingTurn = false
    appendReplay(owner: state.player, action: .pass, in: &state)
    return finishTurn(didPlacePiece: false, in: &state)
  }

  private func updateHighlights(into state: inout State) {
    state.board.previewCoordinates.removeAll()
    guard isHighlightAvailable(state: state) else {
      state.board.highlightedCoordinates.removeAll()
      state.boardFeature.board = state.board
      return
    }
    if let piece = state.pieceSelection {
      state.board.highlightedCoordinates = BoardLogic.highlightPossiblePlacements(for: piece, in: state.board)
      state.boardFeature.board = state.board
    } else {
      state.board.highlightedCoordinates.removeAll()
      state.boardFeature.board = state.board
    }
  }

  private func isHighlightAvailable(state: State) -> Bool {
    state.isHighlight && state.pieceSelection != nil
  }

  private func appendReplay(owner: Player, action: TrunAction, in state: inout State) {
    let index = state.replayTruns.filter { $0.owner == owner }.count
    state.replayTruns.append(Trun(index: index, action: action, owner: owner))
  }
}
