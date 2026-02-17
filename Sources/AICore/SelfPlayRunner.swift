import Domain
import Engine
import Foundation

public struct SelfPlayRunner<Model: PolicyValuePredicting>: Sendable {
  private let config: SelfPlayConfiguration
  private let predictor: Model
  private let moveGenerator: LegalMoveGenerator

  public init(
    config: SelfPlayConfiguration,
    predictor: Model,
    moveGenerator: LegalMoveGenerator = LegalMoveGenerator()
  ) {
    self.config = config
    self.predictor = predictor
    self.moveGenerator = moveGenerator
  }

  public func runBatch(
    progress: (@Sendable (SelfPlayProgress) -> Void)? = nil
  ) async -> SelfPlayBatchResult {
    let startedAt = Date()
    let workerCount = max(1, min(config.parallelism, config.games))
    let progressTracker = ProgressTracker(
      totalGames: config.games,
      startedAt: startedAt,
      callback: progress
    )

    let queue = JobQueue(total: config.games)
    let records: [SelfPlayGameRecord] = await withTaskGroup(of: [SelfPlayGameRecord].self) { group in
      for _ in 0..<workerCount {
        group.addTask {
          var localRecords: [SelfPlayGameRecord] = []
          while let nextIndex = await queue.next() {
            let gameRecord = runSingleGame(index: nextIndex)
            localRecords.append(gameRecord)
            await progressTracker.record(game: gameRecord)
          }
          return localRecords
        }
      }

      var merged: [SelfPlayGameRecord] = []
      for await partial in group {
        merged.append(contentsOf: partial)
      }
      return merged
    }

    let finishedAt = Date()
    let sorted = records.sorted { lhs, rhs in
      lhs.summary.gameId < rhs.summary.gameId
    }

    return SelfPlayBatchResult(
      configuration: config,
      startedAt: startedAt,
      finishedAt: finishedAt,
      games: sorted.map(\.summary),
      positions: sorted.flatMap(\.positions)
    )
  }

  private func runSingleGame(index: Int) -> SelfPlayGameRecord {
    let playerCount = max(2, min(config.players, PlayerID.allCases.count))
    let players = Array(PlayerID.allCases.prefix(playerCount))
    let gameId = String(format: "SELFPLAY-%06d", index + 1)

    var engine = GameEngine(
      state: GameState(
        gameId: gameId,
        players: players,
        authorityId: players[0]
      )
    )

    var rng = SplitMix64(seed: config.baseSeed &+ UInt64(index) &* 0x9E37_79B9)
    let agent = MCTSAgent(
      predictor: predictor,
      moveGenerator: moveGenerator,
      config: config.mcts
    )

    var positions: [TrainingPosition] = []
    positions.reserveCapacity(config.maxTurns)

    var turn = 0
    while engine.state.phase != .finished, turn < config.maxTurns {
      let snapshot = engine.state
      let activePlayer = snapshot.activePlayerId
      let decision = agent.decide(state: snapshot, rng: &rng)
      let legalMoves = moveGenerator.legalMoves(
        for: snapshot,
        playerId: activePlayer,
        maxCount: max(1, config.mcts.maxCandidateMoves)
      )
      let selectedAction = sanitize(
        action: decision.selectedAction,
        legalMoves: legalMoves,
        fallbackPolicy: decision.policy
      )

      positions.append(
        TrainingPosition(
          gameId: gameId,
          ply: turn,
          activePlayer: activePlayer,
          boardEncoding: TrainingEncoding.encodeBoard(snapshot),
          selectedAction: selectedAction,
          policy: decision.policy,
          outcomeByPlayer: []
        )
      )

      if engine.state.apply(action: selectedAction, by: activePlayer) != nil {
        // If policy output was stale or invalid, force a legal pass fallback.
        if engine.state.apply(action: .pass, by: activePlayer) != nil {
          break
        }
      }

      turn += 1
    }

    if engine.state.phase != .finished {
      turn += forceFinalize(engine: &engine, players: players)
    }

    let scores = finalScores(for: engine.state, players: players)
    let scoreValues = players.map { player in
      PlayerValue(playerId: player, value: Double(scores[player, default: 0]))
    }
    let outcomes = outcomeValues(scores: scores, players: players)

    for index in positions.indices {
      positions[index].outcomeByPlayer = outcomes
    }

    let highest = scores.values.max() ?? 0
    let winnerIds = players.filter { scores[$0, default: 0] == highest }

    let summary = SelfPlayGameSummary(
      gameId: gameId,
      turns: turn,
      winnerIds: winnerIds,
      scores: scoreValues
    )

    return SelfPlayGameRecord(summary: summary, positions: positions)
  }

  private func sanitize(
    action: CommandAction,
    legalMoves: [CommandAction],
    fallbackPolicy: [MovePolicyEntry]
  ) -> CommandAction {
    if legalMoves.contains(action) {
      return action
    }
    if let best = fallbackPolicy.max(by: { $0.probability < $1.probability })?.action,
       legalMoves.contains(best) {
      return best
    }
    return legalMoves.first ?? .pass
  }

  private func finalScores(
    for state: GameState,
    players: [PlayerID]
  ) -> [PlayerID: Int] {
    var scores: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
    for cell in state.board.cells {
      guard let owner = cell else { continue }
      scores[owner, default: 0] += 1
    }
    return scores
  }

  private func outcomeValues(
    scores: [PlayerID: Int],
    players: [PlayerID]
  ) -> [PlayerValue] {
    let average = Double(scores.values.reduce(0, +)) / Double(max(1, players.count))
    let scale = Double(max(1, BoardConstants.boardCellCount))

    return players.map { player in
      let raw = Double(scores[player, default: 0])
      let value = max(-1, min(1, (raw - average) / scale))
      return PlayerValue(playerId: player, value: value)
    }
  }

  private func forceFinalize(engine: inout GameEngine, players: [PlayerID]) -> Int {
    var safeGuard = 0
    while engine.state.phase != .finished, safeGuard < players.count * 8 {
      let active = engine.state.activePlayerId
      if engine.state.hasAnyLegalMove(for: active) {
        let legal = moveGenerator.legalMoves(for: engine.state, playerId: active, maxCount: 1)
        if let action = legal.first, action != .pass,
           engine.state.apply(action: action, by: active) == nil {
          safeGuard += 1
          continue
        }
      }
      _ = engine.state.apply(action: .pass, by: active)
      safeGuard += 1
    }
    return safeGuard
  }
}

private actor JobQueue {
  private var nextIndex: Int
  private let total: Int

  init(total: Int) {
    self.nextIndex = 0
    self.total = total
  }

  func next() -> Int? {
    guard nextIndex < total else { return nil }
    defer { nextIndex += 1 }
    return nextIndex
  }
}

private actor ProgressTracker {
  private let totalGames: Int
  private let startedAt: Date
  private let callback: (@Sendable (SelfPlayProgress) -> Void)?
  private let reportEvery: Int

  private var completedGames = 0
  private var generatedPositions = 0
  private var lastReportedCompleted = 0

  init(
    totalGames: Int,
    startedAt: Date,
    callback: (@Sendable (SelfPlayProgress) -> Void)?
  ) {
    self.totalGames = max(0, totalGames)
    self.startedAt = startedAt
    self.callback = callback
    self.reportEvery = max(1, totalGames / 100)
  }

  func record(game: SelfPlayGameRecord) {
    completedGames += 1
    generatedPositions += game.positions.count

    guard let callback else { return }
    let shouldReport = completedGames == 1
      || completedGames == totalGames
      || (completedGames - lastReportedCompleted) >= reportEvery
    guard shouldReport else { return }
    lastReportedCompleted = completedGames

    let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
    let gamesPerSec = Double(completedGames) / elapsed
    let remaining = max(0, totalGames - completedGames)
    let eta = gamesPerSec > 0 ? Double(remaining) / gamesPerSec : nil

    callback(
      SelfPlayProgress(
        completedGames: completedGames,
        totalGames: totalGames,
        generatedPositions: generatedPositions,
        elapsedSec: elapsed,
        gamesPerSec: gamesPerSec,
        etaSec: eta
      )
    )
  }
}
