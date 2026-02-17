import AICore
import Domain
import Testing

extension AppBaseSuite {
  @Test
  func legalMoveGeneratorFindsOpeningPlacements() {
    let state = GameState(gameId: "AI-LEGAL-001", players: [.blue, .yellow], authorityId: .blue)
    let generator = LegalMoveGenerator()

    let moves = generator.legalMoves(for: state, playerId: .blue, maxCount: nil)

    #expect(!moves.isEmpty)
    #expect(moves.contains(.place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0))))
    #expect(!moves.contains(.pass))
  }

  @Test
  func selfPlayRunnerGeneratesPositionsAndOutcomes() async {
    let config = SelfPlayConfiguration(
      games: 1,
      players: 2,
      maxTurns: 8,
      parallelism: 1,
      baseSeed: 42,
      mcts: MCTSConfiguration(
        simulations: 4,
        explorationConstant: 1.25,
        maxCandidateMoves: 8,
        temperature: 0
      )
    )

    let runner = SelfPlayRunner(
      config: config,
      predictor: HeuristicPolicyValuePredictor()
    )

    let result = await runner.runBatch()

    #expect(result.games.count == 1)
    #expect(!result.positions.isEmpty)
    #expect(result.games[0].scores.count == 2)
    #expect(result.positions.allSatisfy { $0.outcomeByPlayer.count == 2 })
  }
}
