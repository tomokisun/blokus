import Foundation
import Testing
import Domain
import Engine
import Persistence
import Connector

#if canImport(SwiftUI)
import SwiftUI
import DesignSystem
import Features

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
}
#endif

#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))

import Features

extension AppBaseSuite {

  // MARK: selectPiece

  @Test
  @MainActor
  func selectPieceSetsIdAndResetsVariantIndex() {
    let vm = GameViewModel()
    // Initially no piece selected
    #expect(vm.selectedPieceId == nil)
    #expect(vm.selectedVariantIndex == 0)

    // Select a piece
    let pieceId = PieceLibrary.pieces[0].id
    vm.selectPiece(pieceId)
    #expect(vm.selectedPieceId == pieceId)
    #expect(vm.selectedVariantIndex == 0)

    // Manually change variant index then select another piece – index resets
    vm.selectedVariantIndex = 3
    let secondPieceId = PieceLibrary.pieces[5].id
    vm.selectPiece(secondPieceId)
    #expect(vm.selectedPieceId == secondPieceId)
    #expect(vm.selectedVariantIndex == 0)
  }

  // MARK: rotatePiece

  @Test
  @MainActor
  func rotatePieceWithNoPieceSelectedDoesNothing() {
    let vm = GameViewModel()
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 0)
    #expect(vm.selectedPieceId == nil)
  }

  @Test
  @MainActor
  func rotatePieceIncrementsVariantForAsymmetricPiece() {
    let vm = GameViewModel()
    // Use an L-shaped piece that has 8 unique variants
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)
    let variants = piece.variants
    #expect(variants.count == 8)

    // Rotate should move to the next rotation (index 2), not just +1
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 2)

    // Rotate again from index 2 → index 4
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 4)

    // Rotate again from index 4 → index 6
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 6)

    // Rotate again from index 6 → wraps back to 0
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func rotatePieceWrapsAroundCorrectly() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)

    // Rotate through all 4 rotations, should wrap back to start
    for _ in 0..<4 {
      vm.rotatePiece()
    }
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func rotatePieceFromFlippedState() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)
    #expect(piece.variants.count == 8)

    // Flip first to go to index 1 (rot0-flip)
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 1)

    let beforeRotate = vm.selectedPieceVariant!

    // Rotate from flipped state should produce a geometrically rotated variant
    vm.rotatePiece()
    let afterRotate = vm.selectedPieceVariant!

    // The variant should change (rotation of an asymmetric flipped piece produces a different shape)
    #expect(beforeRotate != afterRotate)

    // Verify the result is a valid variant of the piece
    #expect(piece.variants.contains(afterRotate))
  }

  // MARK: flipPiece

  @Test
  @MainActor
  func flipPieceWithNoPieceSelectedDoesNothing() {
    let vm = GameViewModel()
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 0)
    #expect(vm.selectedPieceId == nil)
  }

  @Test
  @MainActor
  func flipPieceTogglesFlipState() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)
    #expect(piece.variants.count == 8)

    // From index 0 (rot0) -> flip should go to index 1 (rot0-flip)
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 1)

    // Flip again should go back to index 0 (rot0)
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func flipPieceAfterRotation() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)

    // Rotate to rot1 (index 2)
    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 2)

    // Flip should go to rot1-flip (index 3)
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 3)

    // Flip back should return to rot1 (index 2)
    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 2)
  }

  // MARK: selectedPieceVariant

  @Test
  @MainActor
  func selectedPieceVariantReturnsNilWithoutSelection() {
    let vm = GameViewModel()
    #expect(vm.selectedPieceVariant == nil)
  }

  @Test
  @MainActor
  func selectedPieceVariantReturnsCorrectVariantForIndex() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)

    let variant0 = vm.selectedPieceVariant
    #expect(variant0 == piece.variants[0])

    vm.rotatePiece()
    let variant2 = vm.selectedPieceVariant
    #expect(variant2 == piece.variants[2])
    #expect(variant2 != variant0)
  }

  @Test
  @MainActor
  func rotationActuallyChangesCells() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)

    let before = vm.selectedPieceVariant!
    vm.rotatePiece()
    let after = vm.selectedPieceVariant!

    // The cells should be different after rotation for an asymmetric piece
    #expect(before != after)
  }

  @Test
  @MainActor
  func flipActuallyChangesCells() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "penta-L-5" })!
    vm.selectPiece(piece.id)

    let before = vm.selectedPieceVariant!
    vm.flipPiece()
    let after = vm.selectedPieceVariant!

    // The cells should be different after flipping an asymmetric piece
    #expect(before != after)
  }

  // MARK: Symmetric piece edge cases

  @Test
  @MainActor
  func rotatePieceSymmetricSingleVariant() {
    let vm = GameViewModel()
    // mono-1 is a single cell – only 1 variant
    let piece = PieceLibrary.pieces.first(where: { $0.id == "mono-1" })!
    #expect(piece.variants.count == 1)
    vm.selectPiece(piece.id)

    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func flipPieceSymmetricSingleVariant() {
    let vm = GameViewModel()
    let piece = PieceLibrary.pieces.first(where: { $0.id == "mono-1" })!
    #expect(piece.variants.count == 1)
    vm.selectPiece(piece.id)

    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func rotateAndFlipSquarePiece() {
    let vm = GameViewModel()
    // tetri-O-4 is a square – should have only 1 variant
    let piece = PieceLibrary.pieces.first(where: { $0.id == "tetri-O-4" })!
    #expect(piece.variants.count == 1)
    vm.selectPiece(piece.id)

    vm.rotatePiece()
    #expect(vm.selectedVariantIndex == 0)

    vm.flipPiece()
    #expect(vm.selectedVariantIndex == 0)
  }

  @Test
  @MainActor
  func rotateLinePieceTogglesBetweenTwoVariants() {
    let vm = GameViewModel()
    // domino-2 is a line – should have 2 variants (horizontal and vertical)
    let piece = PieceLibrary.pieces.first(where: { $0.id == "domino-2" })!
    #expect(piece.variants.count == 2)
    vm.selectPiece(piece.id)

    let variant0 = vm.selectedPieceVariant!
    vm.rotatePiece()
    let variant1 = vm.selectedPieceVariant!
    #expect(variant0 != variant1)

    // Rotate again should go back to original
    vm.rotatePiece()
    #expect(vm.selectedPieceVariant == variant0)
  }
}

// MARK: - GameViewModel Group A Tests

extension AppBaseSuite {

  // A1: tapBoard - no piece selected → nothing happens
  @Test @MainActor
  func tapBoardWithNoPieceSelectedDoesNothing() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    let indexBefore = vm.activePlayerIndex
    vm.tapBoard(at: BoardPoint(x: 0, y: 0))
    #expect(vm.activePlayerIndex == indexBefore)
  }

  // A2: tapBoard - direct origin placement (first move at corner)
  @Test @MainActor
  func tapBoardDirectOriginPlacement() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    vm.selectPiece("mono-1")
    // Active player is blue, corner is (0,0)
    vm.tapBoard(at: BoardPoint(x: 0, y: 0))
    // Piece should be placed, selection cleared
    #expect(vm.selectedPieceId == nil)
    #expect(vm.activePlayerIndex == 1)
  }

  // A3: tapBoard - reverse search finds valid placement
  @Test @MainActor
  func tapBoardReverseSearchFindsValidPlacement() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    // domino-2 variant 0: cells at (0,0) and (1,0)
    vm.selectPiece("domino-2")
    // Tapping at (1,0): direct origin (1,0) fails (not at corner),
    // but reverse search computes candidateOrigin = (1-1, 0-0) = (0,0) which IS the blue corner
    vm.tapBoard(at: BoardPoint(x: 1, y: 0))
    #expect(vm.selectedPieceId == nil)
    #expect(vm.activePlayerIndex == 1)
  }

  // A4: tapBoard - reverse search no valid placement
  @Test @MainActor
  func tapBoardReverseSearchNoValidPlacement() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    vm.selectPiece("mono-1")
    // Tap at center, far from corner - no valid placement
    vm.tapBoard(at: BoardPoint(x: 10, y: 10))
    #expect(vm.selectedPieceId == "mono-1") // Still selected, not placed
  }

  // A5: startGame resets all state
  @Test @MainActor
  func startGameResetsState() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: true)
    #expect(vm.isGameStarted == true)
    #expect(vm.showHighlight == true)
    #expect(vm.selectedPieceId == nil)
    #expect(vm.selectedVariantIndex == 0)
  }

  // A6: pass clears selection
  @Test @MainActor
  func passClearsSelection() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    // Remove all pieces for the active player (blue) so pass is legal
    let activeId = vm.currentState.activePlayerId
    vm.engine.state.remainingPieces[activeId] = []
    vm.selectPiece("mono-1")
    #expect(vm.selectedPieceId == "mono-1")
    vm.pass()
    #expect(vm.selectedPieceId == nil)
    #expect(vm.selectedVariantIndex == 0)
  }

  // A7: backToMenu
  @Test @MainActor
  func backToMenuSetsIsGameStartedFalse() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    #expect(vm.isGameStarted == true)
    vm.backToMenu()
    #expect(vm.isGameStarted == false)
  }

  // A8: Computed properties initial state
  @Test @MainActor
  func computedPropertiesInitialState() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    #expect(vm.isGameOver == false)
    #expect(vm.activePlayerIndex == 0)
    #expect(vm.remainingPiecesForCurrentPlayer.count == 21) // All 21 pieces
    #expect(vm.scores.count == 4)
    #expect(vm.scores.allSatisfy { $0.score == 0 })
    #expect(vm.canPass == false) // Has legal moves
    #expect(vm.winnerPlayerIds.isEmpty) // All scores are 0
  }

  // A9: highlightCells
  @Test @MainActor
  func highlightCellsEmptyWhenNoPieceSelected() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: true)
    #expect(vm.highlightCells.isEmpty)
  }

  @Test @MainActor
  func highlightCellsNonEmptyWhenPieceSelectedAndShowHighlightTrue() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: true)
    vm.selectPiece("mono-1")
    // mono-1 has at least one valid placement (corner)
    #expect(!vm.highlightCells.isEmpty)
  }

  @Test @MainActor
  func highlightCellsEmptyWhenShowHighlightFalse() {
    let vm = GameViewModel()
    vm.startGame(showHighlight: false)
    vm.selectPiece("mono-1")
    #expect(vm.highlightCells.isEmpty)
  }

  // A10: selectedPieceVariant edge case - invalid index
  @Test @MainActor
  func selectedPieceVariantReturnsNilForInvalidIndex() {
    let vm = GameViewModel()
    vm.selectPiece("mono-1")
    vm.selectedVariantIndex = 999
    #expect(vm.selectedPieceVariant == nil)
  }
}

#endif
