import Foundation
import Testing
import Domain
import Engine

extension AppBaseSuite {
  @Test
  func boardGeometryAndStateHelpersCover() {
    let cornerState = GameState(gameId: "GAME-GEO", players: [.blue], authorityId: .blue)
    #expect(cornerState.phase == .waiting)
    #expect(cornerState.playerCorner(.blue) == BoardPoint(x: 0, y: 0))
    #expect(BoardPoint(x: 0, y: 0).isInsideBoard)
    #expect(!BoardPoint(x: -1, y: 0).isInsideBoard)
    #expect(BoardPoint(x: 0, y: 0).translated(2, 3) == BoardPoint(x: 2, y: 3))
    #expect(cornerState.boardPoint(for: 99) == BoardPoint(x: 19, y: 4))

    var state = GameState(gameId: "GAME-GEO", players: [.blue, .yellow], authorityId: .blue)
    #expect(state.canPlace(pieceId: "unknown", variantId: 0, origin: .init(x: 0, y: 0), playerId: .blue) == false)

    _ = state.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
    let illegalSide = state.apply(
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 1, y: 0)),
      by: .yellow
    )
    #expect(illegalSide == .invalidPlacement)

    state.activeIndex = 1
    let invalidFirstMove = state.apply(
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 1, y: 1)),
      by: .yellow
    )
    #expect(invalidFirstMove == .invalidPlacement)

    let legalFirstMove = state.apply(
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 19, y: 19)),
      by: .yellow
    )
    #expect(legalFirstMove == nil)
    #expect(state.activeIndex == 0)

    state.remainingPieces[.blue] = []
    state.remainingPieces[.yellow] = []
    #expect(state.hasAnyLegalMove(for: .blue) == false)
    #expect(state.hasAnyLegalMove(for: .yellow) == false)
    #expect(state.hasAnyLegalMove(for: .blue) == false)
    #expect(state.hasAnyLegalMove(for: .yellow) == false)
  }

  @Test
  func gameStateInitialFactoryAndRetryDelayCap() {
    let initial = GameState.initial(gameId: "GAME-INIT", players: [.blue, .yellow, .red], authorityId: .yellow)
    #expect(initial.gameId == "GAME-INIT")
    #expect(initial.phase == .playing)
    #expect(initial.authority.coordinationAuthorityId == .yellow)
    #expect(initial.turnOrder == [.blue, .yellow, .red])
    #expect(initial.remainingPieces[.blue]?.count == PieceLibrary.pieces.count)

    let waiting = GameState.initial(gameId: "GAME-WAIT", players: [.green], authorityId: .green)
    #expect(waiting.phase == .waiting)

    var engine = GameEngine(state: initial)
    engine.state.eventGaps = [
      EventGap(
        fromSeq: 1,
        toSeq: 2,
        detectedAt: defaultDate,
        retryCount: 5,
        nextRetryAt: defaultDate,
        lastError: "test",
        maxRetries: 10,
        deadlineAt: defaultDate.addingTimeInterval(60)
      )
    ]
    engine.tick(now: defaultDate)
    #expect(engine.state.eventGaps.count == 1)
    #expect(engine.state.eventGaps[0].retryCount == 6)
    #expect(abs(engine.state.eventGaps[0].nextRetryAt.timeIntervalSince1970 - (defaultDate.timeIntervalSince1970 + 16)) < 0.001)
  }

  @Test
  func registerGapMergesOverlappingIncomingRanges() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-GAP", players: [.blue, .yellow], authorityId: .blue)
    )
    let firstGapEvent = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: Data([0x01]),
      expectedSeq: 0,
      coordinationSeq: 5,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .blue,
      payload: .pass,
      stateFingerprintBefore: "before",
      stateFingerprintAfter: "after",
      status: MoveEventStatus.committed,
      chainHash: "",
      prevChainHash: "",
      createdAt: defaultDate
    )
    _ = engine.applyRemoteEvents([firstGapEvent])

    let secondGapEvent = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: Data([0x02]),
      expectedSeq: 0,
      coordinationSeq: 4,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .blue,
      payload: .pass,
      stateFingerprintBefore: "before",
      stateFingerprintAfter: "after",
      status: MoveEventStatus.committed,
      chainHash: "",
      prevChainHash: "",
      createdAt: defaultDate
    )
    let second = engine.applyRemoteEvents([secondGapEvent])
    #expect(second.queuedRanges.count == 1)
    #expect(!engine.state.eventGaps.isEmpty)
    #expect(engine.state.eventGaps[0].fromSeq == 1)
    #expect(engine.state.eventGaps[0].toSeq == 5)
    _ = second
  }

  @Test
  func playerCornerReturnsCorrectCornerForAllPlayers() {
    let state = GameState(gameId: "GAME-CORNER", players: [.blue, .yellow, .red, .green], authorityId: .blue)
    #expect(state.playerCorner(.blue) == BoardPoint(x: 0, y: 0))
    #expect(state.playerCorner(.yellow) == BoardPoint(x: 19, y: 19))
    #expect(state.playerCorner(.red) == BoardPoint(x: 19, y: 0))
    #expect(state.playerCorner(.green) == BoardPoint(x: 0, y: 19))
  }

  @Test
  func canPlaceRejectsOwnColorSideAdjacency() {
    var state = GameState(gameId: "GAME-SIDE", players: [.blue, .yellow], authorityId: .blue)
    // A places mono-1 at corner (0,0)
    let result = state.apply(action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)), by: .blue)
    #expect(result == nil)
    // Now it's B's turn, skip B
    _ = state.apply(action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 19, y: 19)), by: .yellow)
    // A tries to place at (1,0) - side adjacent to own piece at (0,0)
    // A placing domino-2 at origin (1,0) with variant 0 (horizontal) would put cells at (1,0) and (2,0)
    // (1,0) is side-adjacent to A's piece at (0,0) → should be rejected
    #expect(state.canPlace(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 1, y: 0), playerId: .blue) == false)
  }

  @Test
  func canPlaceAllowsOtherPlayerSideAdjacency() {
    var state = GameState(gameId: "GAME-ADJ-OK", players: [.blue, .yellow], authorityId: .blue)
    // Manually set up board state:
    // A has a piece at (11,10)
    state.board[BoardPoint(x: 11, y: 10)] = .blue
    state.remainingPieces[.blue]!.remove("mono-1")
    // B has already placed at (12,12)
    state.board[BoardPoint(x: 12, y: 12)] = .yellow
    state.remainingPieces[.yellow]!.remove("mono-1")

    // B tries to place domino-2 at (10,11) in vertical orientation:
    // domino-2 variant 1 (vertical): cells at (10,11) and (10,12)
    // (10,11) to A(11,10): diff=(-1,1) - diagonal, not side
    // Let me recalculate: A is at (11, 10). New piece at (10,11).
    // diff = (10-11, 11-10) = (-1, 1) - diagonal
    // This doesn't test side adjacency!
    //
    // New approach: Use domino-2 horizontal at (10,10)
    // Cells: (10,10), (11,10)
    // A is at (11,10) - OVERLAP! Can't do that.
    //
    // Final approach: A at (10,10), B at (12,12), place domino vertical at (11,10)
    state.board[BoardPoint(x: 11, y: 10)] = nil
    state.board[BoardPoint(x: 10, y: 10)] = .blue
    // domino-2 variant 1 (vertical): origin (11,10), cells at (11,10) and (11,11)
    // (11,10) to A(10,10): diff=(1,0) - SIDE ✓
    // (11,10) to B(12,12): diff=(1,2) - not diagonal
    // (11,11) to B(12,12): diff=(1,1) - diagonal ✓
    // (11,10) neighbors: (10,10)[A], (12,10), (11,9), (11,11)[part of piece]
    // (11,11) neighbors: (10,11), (12,11), (11,10)[part of piece], (11,12)
    // Neither cell is side-adjacent to B ✓
    #expect(state.canPlace(pieceId: "domino-2", variantId: 1, origin: BoardPoint(x: 11, y: 10), playerId: .yellow) == true)
  }

  @Test
  func canPlaceRejectsPlacementWithNoDiagonalTouchToOwnColor() {
    var state = GameState(gameId: "GAME-DIAG", players: [.blue, .yellow], authorityId: .blue)
    // A places mono-1 at corner (0,0)
    _ = state.apply(action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)), by: .blue)
    // B places mono-1 at corner (19,19)
    _ = state.apply(action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 19, y: 19)), by: .yellow)
    // A's second move at (5,5) - far from (0,0), no diagonal touch to own → rejected
    #expect(state.canPlace(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 5, y: 5), playerId: .blue) == false)
    // A's second move at (1,1) - diagonal to own (0,0) → accepted
    #expect(state.canPlace(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 1, y: 1), playerId: .blue) == true)
  }

  @Test
  func canPlaceRejectsOutOfBoundsCellsNearEdge() {
    let state = GameState(gameId: "GAME-OOB", players: [.blue, .yellow], authorityId: .blue)
    // domino-2 variant 0 is horizontal: cells [(0,0),(1,0)]. At origin (19,0), cell (20,0) is OOB.
    #expect(state.canPlace(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 19, y: 0), playerId: .blue) == false)
    // domino-2 variant 1 is vertical: cells [(0,0),(0,1)]. At origin (0,19), cell (0,20) is OOB.
    #expect(state.canPlace(pieceId: "domino-2", variantId: 1, origin: BoardPoint(x: 0, y: 19), playerId: .blue) == false)
  }

  @Test
  func hasAnyLegalMoveReturnsFalseForUnknownPlayer() {
    let state = GameState(gameId: "GAME-UNKNOWN", players: [.blue, .yellow], authorityId: .blue)
    #expect(state.hasAnyLegalMove(for: .green) == false)
  }
}
