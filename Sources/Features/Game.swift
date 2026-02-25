import AICore
import ComposableArchitecture
import Domain
import Foundation

@Reducer
public struct Game {
  @ObservableState
  public struct State: Equatable {
    public var gameState: GameState
    public var selectedPieceId: String?
    public var selectedVariantIndex: Int
    public var showHighlight: Bool
    public var isAIThinking: Bool

    public init(
      gameState: GameState = GameState(
        gameId: UUID().uuidString,
        players: Array(PlayerID.allCases),
        authorityId: .blue
      ),
      selectedPieceId: String? = nil,
      selectedVariantIndex: Int = 0,
      showHighlight: Bool = true,
      isAIThinking: Bool = false
    ) {
      self.gameState = gameState
      self.selectedPieceId = selectedPieceId
      self.selectedVariantIndex = selectedVariantIndex
      self.showHighlight = showHighlight
      self.isAIThinking = isAIThinking
    }

    public var isGameOver: Bool {
      gameState.phase == .finished
    }

    public var activePlayerIndex: Int {
      gameState.activeIndex
    }

    public var isActivePlayerAI: Bool {
      gameState.activePlayerIsAI
    }

    public var remainingPiecesForCurrentPlayer: [Piece] {
      let activeId = gameState.activePlayerId
      let remaining = gameState.remainingPieces[activeId] ?? []
      return PieceLibrary.pieces.filter { remaining.contains($0.id) }
    }

    public var scores: [(playerId: PlayerID, score: Int)] {
      gameState.turnOrder.map { playerId in
        let score = gameState.board.filter { $0 == playerId }.count
        return (playerId: playerId, score: score)
      }
    }

    public var canPass: Bool {
      !gameState.hasAnyLegalMove(for: gameState.activePlayerId)
    }

    public var selectedPieceVariant: [BoardPoint]? {
      guard
        let pieceId = selectedPieceId,
        let piece = PieceLibrary.pieceById[pieceId]
      else {
        return nil
      }

      let variants = piece.variants
      guard selectedVariantIndex >= 0, selectedVariantIndex < variants.count else {
        return nil
      }

      return variants[selectedVariantIndex]
    }

    public var highlightCells: Set<BoardPoint> {
      guard
        showHighlight,
        let pieceId = selectedPieceId,
        let variant = selectedPieceVariant
      else {
        return []
      }

      let activeId = gameState.activePlayerId
      var result = Set<BoardPoint>()
      for y in 0..<BoardConstants.boardSize {
        for x in 0..<BoardConstants.boardSize {
          let origin = BoardPoint(x: x, y: y)
          if gameState.canPlace(
            pieceId: pieceId,
            variantId: selectedVariantIndex,
            origin: origin,
            playerId: activeId
          ) {
            for cell in variant {
              let absolute = BoardPoint(x: cell.x + origin.x, y: cell.y + origin.y)
              result.insert(absolute)
            }
          }
        }
      }
      return result
    }

    public var winnerPlayerIds: [PlayerID] {
      let playerScores = scores
      guard let maxScore = playerScores.map(\.score).max(), maxScore > 0 else {
        return []
      }
      return playerScores.filter { $0.score == maxScore }.map(\.playerId)
    }
  }

  public enum Action {
    case boardCellTapped(BoardPoint)
    case flipButtonTapped
    case newGameButtonTapped
    case passButtonTapped
    case pieceTapped(String)
    case rotateButtonTapped
    case aiMoveCompleted(CommandAction)
    case triggerAITurn
    case delegate(Delegate)

    public enum Delegate {
      case backToMenu
    }
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .pieceTapped(pieceId):
        guard !state.isActivePlayerAI else { return .none }
        state.selectedPieceId = pieceId
        state.selectedVariantIndex = 0
        return .none

      case .rotateButtonTapped:
        guard !state.isActivePlayerAI else { return .none }
        guard
          let pieceId = state.selectedPieceId,
          let piece = PieceLibrary.pieceById[pieceId]
        else {
          return .none
        }

        let variants = piece.variants
        guard !variants.isEmpty, state.selectedVariantIndex < variants.count else {
          return .none
        }

        let current = variants[state.selectedVariantIndex]
        let rotated = Self.canonicalize(current.map { BoardPoint(x: $0.y, y: -$0.x) })
        if let index = variants.firstIndex(where: { Self.canonicalize($0) == rotated }) {
          state.selectedVariantIndex = index
        } else {
          state.selectedVariantIndex = (state.selectedVariantIndex + 1) % variants.count
        }
        return .none

      case .flipButtonTapped:
        guard !state.isActivePlayerAI else { return .none }
        guard
          let pieceId = state.selectedPieceId,
          let piece = PieceLibrary.pieceById[pieceId]
        else {
          return .none
        }

        let variants = piece.variants
        guard !variants.isEmpty, state.selectedVariantIndex < variants.count else {
          return .none
        }

        let current = variants[state.selectedVariantIndex]
        let flipped = Self.canonicalize(current.map { BoardPoint(x: -$0.x, y: $0.y) })
        if let index = variants.firstIndex(where: { Self.canonicalize($0) == flipped }) {
          state.selectedVariantIndex = index
        } else {
          state.selectedVariantIndex = (state.selectedVariantIndex + 1) % variants.count
        }
        return .none

      case let .boardCellTapped(point):
        guard !state.isGameOver, !state.isActivePlayerAI else {
          return .none
        }
        let effect = placeSelectedPiece(at: point, state: &state)
        return effect.concatenate(with: triggerAIIfNeeded(state: state))

      case .passButtonTapped:
        guard !state.isActivePlayerAI else { return .none }
        let activePlayer = state.gameState.activePlayerId
        _ = state.gameState.apply(action: .pass, by: activePlayer)
        clearSelection(state: &state)
        return triggerAIIfNeeded(state: state)

      case .triggerAITurn:
        guard !state.isGameOver, state.isActivePlayerAI else {
          state.isAIThinking = false
          return .none
        }
        state.isAIThinking = true
        let gameState = state.gameState
        return .run { send in
          let action = await Self.computeAIMove(gameState: gameState)
          await send(.aiMoveCompleted(action))
        }

      case let .aiMoveCompleted(commandAction):
        state.isAIThinking = false
        guard !state.isGameOver else { return .none }
        let activePlayer = state.gameState.activePlayerId
        _ = state.gameState.apply(action: commandAction, by: activePlayer)
        clearSelection(state: &state)
        return triggerAIIfNeeded(state: state)

      case .newGameButtonTapped:
        return .send(.delegate(.backToMenu))

      case .delegate:
        return .none
      }
    }
  }

  private func triggerAIIfNeeded(state: State) -> Effect<Action> {
    guard !state.isGameOver, state.isActivePlayerAI else { return .none }
    return .run { send in
      try await Task.sleep(for: .milliseconds(300))
      await send(.triggerAITurn)
    }
  }

  private static func computeAIMove(gameState: GameState) async -> CommandAction {
    await withCheckedContinuation { continuation in
      let predictor = Self.loadPredictor()
      let agent = MCTSAgent(
        predictor: predictor,
        config: MCTSConfiguration(
          simulations: 160,
          maxCandidateMoves: 48,
          temperature: 0
        )
      )
      var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
      let decision = agent.decide(state: gameState, rng: &rng)
      continuation.resume(returning: decision.selectedAction)
    }
  }

  nonisolated(unsafe) private static var cachedModel: TrainedPolicyValueModel?

  private static func loadPredictor() -> LearnedPolicyValuePredictor {
    if let model = cachedModel {
      return LearnedPolicyValuePredictor(model: model)
    }

    if let url = Bundle.main.url(forResource: "model-best", withExtension: "json"),
       let model = try? TrainedModelIO.load(from: url) {
      cachedModel = model
      return LearnedPolicyValuePredictor(model: model)
    }

    // No bundled model found — use heuristic via LearnedPolicyValuePredictor's fallback
    let emptyModel = TrainedPolicyValueModel(
      createdAt: Date(),
      label: "heuristic-fallback",
      policyBlend: 0,
      valueBlend: 0,
      passBias: 0,
      actionBiasByKey: [:],
      pieceBiasById: [:],
      valueModel: LinearValueModel(
        intercept: 0, leadWeight: 0, progressWeight: 0,
        occupancyWeight: 0, playerBiasById: [:]
      ),
      metrics: ModelTrainingMetrics(
        positionCount: 0, uniqueActionCount: 0, storedActionBiasCount: 0,
        uniquePieceCount: 0, valueMSE: 0, averageTarget: 0
      )
    )
    return LearnedPolicyValuePredictor(model: emptyModel)
  }

  private static func canonicalize(_ points: [BoardPoint]) -> [BoardPoint] {
    guard let minX = points.map(\.x).min(), let minY = points.map(\.y).min() else {
      return []
    }
    return points
      .map { BoardPoint(x: $0.x - minX, y: $0.y - minY) }
      .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
  }

  private func clearSelection(state: inout State) {
    state.selectedPieceId = nil
    state.selectedVariantIndex = 0
  }

  private func placeSelectedPiece(at point: BoardPoint, state: inout State) -> Effect<Action> {
    guard
      let pieceId = state.selectedPieceId,
      let variant = state.selectedPieceVariant
    else {
      return .none
    }

    let activeId = state.gameState.activePlayerId
    if state.gameState.canPlace(
      pieceId: pieceId,
      variantId: state.selectedVariantIndex,
      origin: point,
      playerId: activeId
    ) {
      _ = state.gameState.apply(
        action: .place(pieceId: pieceId, variantId: state.selectedVariantIndex, origin: point),
        by: activeId
      )
      clearSelection(state: &state)
      return .none
    }

    var bestOrigin: BoardPoint?
    var bestDistance = Int.max

    for cell in variant {
      let candidateOrigin = BoardPoint(x: point.x - cell.x, y: point.y - cell.y)
      guard candidateOrigin.x >= 0, candidateOrigin.y >= 0 else {
        continue
      }

      if state.gameState.canPlace(
        pieceId: pieceId,
        variantId: state.selectedVariantIndex,
        origin: candidateOrigin,
        playerId: activeId
      ) {
        let distance = abs(candidateOrigin.x - point.x) + abs(candidateOrigin.y - point.y)
        if distance < bestDistance {
          bestDistance = distance
          bestOrigin = candidateOrigin
        }
      }
    }

    if let origin = bestOrigin {
      _ = state.gameState.apply(
        action: .place(pieceId: pieceId, variantId: state.selectedVariantIndex, origin: origin),
        by: activeId
      )
      clearSelection(state: &state)
    }

    return .none
  }
}
