import ComposableArchitecture
import Connector
import Domain
import Engine
import Foundation
import Persistence
import Testing

#if canImport(SwiftUI)
import DesignSystem
import Features
import SwiftUI

extension AppBaseSuite {
  @Test
  @MainActor
  func dashboardAndPreviewViewsExecuteBody() {
    let metrics = OperationalMetrics(
      gapOpenCount: 3,
      gapRecoveryDurationMs: 1200,
      queuedCount: 2,
      forkCount: 1,
      orphanRate: 0.2,
      latestRetryCount: 4
    )
    let context = ReadOnlyContext(
      gameId: "GAME-UI",
      phase: .readOnly,
      openGaps: [EventGap(
        fromSeq: 1,
        toSeq: 2,
        detectedAt: defaultDate,
        retryCount: 3,
        nextRetryAt: defaultDate.addingTimeInterval(1),
        lastError: "test",
        maxRetries: 5,
        deadlineAt: defaultDate.addingTimeInterval(30)
      )],
      latestMatchedCoordinationSeq: 0,
      lastSeenOrphanEventId: UUID(),
      lastSeenOrphanReason: "conflict",
      retryCount: 3,
      lastFailureAt: defaultDate
    )

    let dashboard = OperationalDashboard(metrics: metrics, readOnlyContext: context)
    #expect(context.retryCount == 3)
    _ = String(describing: dashboard.body)

    let dashboardWithoutContext = OperationalDashboard(metrics: metrics, readOnlyContext: nil)
    _ = String(describing: dashboardWithoutContext.body)

    let preview = SnapshotPreview()
    _ = String(describing: preview.body)
  }

  @Test
  @MainActor
  func rootStartsAndStopsGame() async {
    let store = TestStore(initialState: Root.State()) {
      Root()
    }
    store.exhaustivity = .off

    await store.send(.newGame(.delegate(.startGame(showHighlight: false))))
    #expect(store.state.game?.showHighlight == false)

    await store.send(.game(.delegate(.backToMenu)))
    #expect(store.state.game == nil)
  }

  @Test
  @MainActor
  func newGameBindingUpdatesShowHighlight() async {
    let store = TestStore(initialState: NewGame.State()) {
      NewGame()
    }
    store.exhaustivity = .off

    await store.send(.binding(.set(\.showHighlight, false))) {
      $0.showHighlight = false
    }
  }

  @Test
  @MainActor
  func selectPieceSetsIdAndResetsVariantIndex() async {
    let store = TestStore(initialState: Game.State(showHighlight: true)) {
      Game()
    }
    store.exhaustivity = .off

    let first = PieceLibrary.pieces[0].id
    await store.send(.pieceTapped(first)) {
      $0.selectedPieceId = first
      $0.selectedVariantIndex = 0
    }

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedVariantIndex >= 0)

    let second = PieceLibrary.pieces[5].id
    await store.send(.pieceTapped(second)) {
      $0.selectedPieceId = second
      $0.selectedVariantIndex = 0
    }
  }

  @Test
  @MainActor
  func rotatePieceForAsymmetricPiece() async {
    let store = TestStore(initialState: Game.State(showHighlight: true)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("penta-L-5")) {
      $0.selectedPieceId = "penta-L-5"
      $0.selectedVariantIndex = 0
    }

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedVariantIndex == 2)

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedVariantIndex == 4)

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedVariantIndex == 6)

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func flipPieceTogglesVariantPair() async {
    let store = TestStore(initialState: Game.State(showHighlight: true)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("penta-L-5")) {
      $0.selectedPieceId = "penta-L-5"
      $0.selectedVariantIndex = 0
    }

    await store.send(.flipButtonTapped)
    #expect(store.state.selectedVariantIndex == 1)

    await store.send(.flipButtonTapped)
    #expect(store.state.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func rotatePieceWithNoSelectionDoesNothing() async {
    let store = TestStore(initialState: Game.State(showHighlight: true)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.rotateButtonTapped)
    #expect(store.state.selectedPieceId == nil)
    #expect(store.state.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func tapBoardPlacesPieceAtOriginAndClearsSelection() async {
    let store = TestStore(initialState: Game.State(showHighlight: false)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("mono-1")) {
      $0.selectedPieceId = "mono-1"
      $0.selectedVariantIndex = 0
    }

    await store.send(.boardCellTapped(BoardPoint(x: 0, y: 0)))

    #expect(store.state.selectedPieceId == nil)
    #expect(store.state.selectedVariantIndex == 0)
    #expect(store.state.gameState.activeIndex == 1)
    #expect(store.state.gameState.board[BoardPoint(x: 0, y: 0)] == .blue)
  }

  @Test
  @MainActor
  func tapBoardUsesReverseSearch() async {
    let store = TestStore(initialState: Game.State(showHighlight: false)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("domino-2")) {
      $0.selectedPieceId = "domino-2"
      $0.selectedVariantIndex = 0
    }

    await store.send(.boardCellTapped(BoardPoint(x: 1, y: 0)))

    #expect(store.state.selectedPieceId == nil)
    #expect(store.state.gameState.activeIndex == 1)
    #expect(store.state.gameState.board[BoardPoint(x: 0, y: 0)] == .blue)
    #expect(store.state.gameState.board[BoardPoint(x: 1, y: 0)] == .blue)
  }

  @Test
  @MainActor
  func tapBoardInvalidPositionKeepsSelection() async {
    let store = TestStore(initialState: Game.State(showHighlight: false)) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("mono-1")) {
      $0.selectedPieceId = "mono-1"
      $0.selectedVariantIndex = 0
    }

    await store.send(.boardCellTapped(BoardPoint(x: 10, y: 10)))
    #expect(store.state.selectedPieceId == "mono-1")
    #expect(store.state.gameState.activeIndex == 0)
  }

  @Test
  @MainActor
  func passClearsSelectionAndAdvancesTurnWhenLegal() async {
    var gameState = GameState(
      gameId: "GAME-PASS",
      players: Array(PlayerID.allCases),
      authorityId: .blue
    )
    let activePlayer = gameState.activePlayerId
    gameState.remainingPieces[activePlayer] = []

    let store = TestStore(
      initialState: Game.State(gameState: gameState, showHighlight: false)
    ) {
      Game()
    }
    store.exhaustivity = .off

    await store.send(.pieceTapped("mono-1")) {
      $0.selectedPieceId = "mono-1"
      $0.selectedVariantIndex = 0
    }

    await store.send(.passButtonTapped)

    #expect(store.state.selectedPieceId == nil)
    #expect(store.state.selectedVariantIndex == 0)
    #expect(store.state.gameState.activeIndex == 1)
  }

  @Test
  @MainActor
  func highlightCellsReflectSelectionAndSetting() async {
    let enabledStore = TestStore(initialState: Game.State(showHighlight: true)) {
      Game()
    }
    enabledStore.exhaustivity = .off

    await enabledStore.send(.pieceTapped("mono-1")) {
      $0.selectedPieceId = "mono-1"
      $0.selectedVariantIndex = 0
    }
    #expect(!enabledStore.state.highlightCells.isEmpty)

    let disabledStore = TestStore(initialState: Game.State(showHighlight: false)) {
      Game()
    }
    disabledStore.exhaustivity = .off
    await disabledStore.send(.pieceTapped("mono-1")) {
      $0.selectedPieceId = "mono-1"
      $0.selectedVariantIndex = 0
    }
    #expect(disabledStore.state.highlightCells.isEmpty)
  }

  @Test
  @MainActor
  func selectedPieceVariantReturnsNilForInvalidIndex() async {
    let state = Game.State(
      selectedPieceId: "mono-1",
      selectedVariantIndex: 999,
      showHighlight: false
    )

    let store = TestStore(initialState: state) {
      Game()
    }
    store.exhaustivity = .off

    #expect(store.state.selectedPieceVariant == nil)
  }
}

#endif
