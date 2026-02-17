import Domain
import Engine
import Foundation

public struct ModelEvaluationConfiguration: Codable, Hashable, Sendable {
  public var games: Int
  public var players: Int
  public var maxTurns: Int
  public var parallelism: Int
  public var baseSeed: UInt64
  public var mcts: MCTSConfiguration

  public init(
    games: Int,
    players: Int,
    maxTurns: Int,
    parallelism: Int,
    baseSeed: UInt64,
    mcts: MCTSConfiguration
  ) {
    self.games = games
    self.players = players
    self.maxTurns = maxTurns
    self.parallelism = parallelism
    self.baseSeed = baseSeed
    self.mcts = mcts
  }
}

public struct ModelEvaluationProgress: Sendable {
  public var completedGames: Int
  public var totalGames: Int
  public var elapsedSec: TimeInterval
  public var gamesPerSec: Double
  public var etaSec: TimeInterval?

  public init(
    completedGames: Int,
    totalGames: Int,
    elapsedSec: TimeInterval,
    gamesPerSec: Double,
    etaSec: TimeInterval?
  ) {
    self.completedGames = completedGames
    self.totalGames = totalGames
    self.elapsedSec = elapsedSec
    self.gamesPerSec = gamesPerSec
    self.etaSec = etaSec
  }
}

public struct ModelEvaluationResult: Codable, Sendable {
  public var configuration: ModelEvaluationConfiguration
  public var startedAt: Date
  public var finishedAt: Date
  public var gameCount: Int
  public var winRateA: Double
  public var winRateB: Double
  public var avgScoreA: Double
  public var avgScoreB: Double
  public var avgRankA: Double
  public var avgRankB: Double
  public var averageTurns: Double
  public var estimatedEloA: Double
  public var estimatedEloB: Double

  public init(
    configuration: ModelEvaluationConfiguration,
    startedAt: Date,
    finishedAt: Date,
    gameCount: Int,
    winRateA: Double,
    winRateB: Double,
    avgScoreA: Double,
    avgScoreB: Double,
    avgRankA: Double,
    avgRankB: Double,
    averageTurns: Double,
    estimatedEloA: Double,
    estimatedEloB: Double
  ) {
    self.configuration = configuration
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.gameCount = gameCount
    self.winRateA = winRateA
    self.winRateB = winRateB
    self.avgScoreA = avgScoreA
    self.avgScoreB = avgScoreB
    self.avgRankA = avgRankA
    self.avgRankB = avgRankB
    self.averageTurns = averageTurns
    self.estimatedEloA = estimatedEloA
    self.estimatedEloB = estimatedEloB
  }
}

public struct ModelEvaluator: Sendable {
  private let configuration: ModelEvaluationConfiguration
  private let moveGenerator: LegalMoveGenerator

  public init(
    configuration: ModelEvaluationConfiguration,
    moveGenerator: LegalMoveGenerator = LegalMoveGenerator()
  ) {
    self.configuration = configuration
    self.moveGenerator = moveGenerator
  }

  public func evaluate(
    modelA: TrainedPolicyValueModel,
    modelB: TrainedPolicyValueModel,
    progress: (@Sendable (ModelEvaluationProgress) -> Void)? = nil
  ) async -> ModelEvaluationResult {
    let startedAt = Date()
    let totalGames = max(1, configuration.games)
    let workers = max(1, min(configuration.parallelism, totalGames))

    let queue = EvaluationJobQueue(total: totalGames)
    let tracker = EvaluationProgressTracker(totalGames: totalGames, startedAt: startedAt, callback: progress)

    let aggregate = await withTaskGroup(of: Aggregate.self) { group in
      for _ in 0..<workers {
        group.addTask {
          var partial = Aggregate()
          while let gameIndex = await queue.next() {
            let result = runSingleGame(index: gameIndex, modelA: modelA, modelB: modelB)
            partial.merge(result)
            await tracker.record()
          }
          return partial
        }
      }

      var merged = Aggregate()
      for await partial in group {
        merged.combine(partial)
      }
      return merged
    }

    let finishedAt = Date()
    let games = Double(max(1, totalGames))

    let winRateA = aggregate.winCreditsA / games
    let winRateB = aggregate.winCreditsB / games
    let avgScoreA = aggregate.seatCountA > 0 ? aggregate.totalScoreA / Double(aggregate.seatCountA) : 0
    let avgScoreB = aggregate.seatCountB > 0 ? aggregate.totalScoreB / Double(aggregate.seatCountB) : 0
    let avgRankA = aggregate.seatCountA > 0 ? aggregate.totalRankA / Double(aggregate.seatCountA) : 0
    let avgRankB = aggregate.seatCountB > 0 ? aggregate.totalRankB / Double(aggregate.seatCountB) : 0
    let averageTurns = aggregate.totalTurns / games

    let pA = min(1 - 1e-6, max(1e-6, winRateA))
    let eloA = 400 * log10(pA / (1 - pA))

    return ModelEvaluationResult(
      configuration: configuration,
      startedAt: startedAt,
      finishedAt: finishedAt,
      gameCount: totalGames,
      winRateA: winRateA,
      winRateB: winRateB,
      avgScoreA: avgScoreA,
      avgScoreB: avgScoreB,
      avgRankA: avgRankA,
      avgRankB: avgRankB,
      averageTurns: averageTurns,
      estimatedEloA: eloA,
      estimatedEloB: -eloA
    )
  }

  private func runSingleGame(
    index: Int,
    modelA: TrainedPolicyValueModel,
    modelB: TrainedPolicyValueModel
  ) -> Aggregate {
    let playerCount = max(2, min(configuration.players, PlayerID.allCases.count))
    let players = Array(PlayerID.allCases.prefix(playerCount))
    let gameId = String(format: "EVAL-%06d", index + 1)

    let controllerByPlayer = Dictionary(uniqueKeysWithValues: players.enumerated().map { offset, playerId in
      let useA = (index + offset) % 2 == 0
      return (playerId, useA)
    })

    let predictorA = LearnedPolicyValuePredictor(model: modelA)
    let predictorB = LearnedPolicyValuePredictor(model: modelB)

    let agentA = MCTSAgent(
      predictor: predictorA,
      moveGenerator: moveGenerator,
      config: configuration.mcts
    )
    let agentB = MCTSAgent(
      predictor: predictorB,
      moveGenerator: moveGenerator,
      config: configuration.mcts
    )

    var engine = GameEngine(
      state: GameState(
        gameId: gameId,
        players: players,
        authorityId: players[0]
      )
    )

    var rng = SplitMix64(seed: configuration.baseSeed &+ UInt64(index) &* 0x517C_C1B7)

    var turns = 0
    while engine.state.phase != .finished, turns < configuration.maxTurns {
      let snapshot = engine.state
      let active = snapshot.activePlayerId
      let legalMoves = moveGenerator.legalMoves(
        for: snapshot,
        playerId: active,
        maxCount: max(1, configuration.mcts.maxCandidateMoves)
      )

      let useA = controllerByPlayer[active, default: true]
      let decision = useA
        ? agentA.decide(state: snapshot, rng: &rng)
        : agentB.decide(state: snapshot, rng: &rng)

      let action = sanitize(
        selected: decision.selectedAction,
        legalMoves: legalMoves,
        fallbackPolicy: decision.policy
      )

      if engine.state.apply(action: action, by: active) != nil {
        if engine.state.apply(action: .pass, by: active) != nil {
          break
        }
      }

      turns += 1
    }

    if engine.state.phase != .finished {
      turns += forceFinalize(engine: &engine, players: players)
    }

    let scores = boardScores(state: engine.state, players: players)
    let ranks = boardRanks(scores: scores, players: players)

    let maxScore = scores.values.max() ?? 0
    let winners = players.filter { scores[$0, default: 0] == maxScore }
    let winnerShare = winners.isEmpty ? 0 : 1.0 / Double(winners.count)

    var result = Aggregate()
    result.totalTurns += Double(turns)

    for player in players {
      let useA = controllerByPlayer[player, default: true]
      let score = Double(scores[player, default: 0])
      let rank = ranks[player, default: Double(players.count)]
      if useA {
        result.totalScoreA += score
        result.totalRankA += rank
        result.seatCountA += 1
      } else {
        result.totalScoreB += score
        result.totalRankB += rank
        result.seatCountB += 1
      }
    }

    for winner in winners {
      let useA = controllerByPlayer[winner, default: true]
      if useA {
        result.winCreditsA += winnerShare
      } else {
        result.winCreditsB += winnerShare
      }
    }

    return result
  }

  private func sanitize(
    selected: CommandAction,
    legalMoves: [CommandAction],
    fallbackPolicy: [MovePolicyEntry]
  ) -> CommandAction {
    if legalMoves.contains(selected) {
      return selected
    }
    if let best = fallbackPolicy.max(by: { $0.probability < $1.probability })?.action,
       legalMoves.contains(best) {
      return best
    }
    return legalMoves.first ?? .pass
  }

  private func boardScores(
    state: GameState,
    players: [PlayerID]
  ) -> [PlayerID: Int] {
    var result = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
    for cell in state.board.cells {
      guard let owner = cell else { continue }
      result[owner, default: 0] += 1
    }
    return result
  }

  private func boardRanks(
    scores: [PlayerID: Int],
    players: [PlayerID]
  ) -> [PlayerID: Double] {
    var result: [PlayerID: Double] = [:]
    for player in players {
      let score = scores[player, default: 0]
      let betterCount = players.reduce(0) { partial, other in
        partial + ((scores[other, default: 0] > score) ? 1 : 0)
      }
      result[player] = Double(1 + betterCount)
    }
    return result
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

private struct Aggregate: Sendable {
  var winCreditsA = 0.0
  var winCreditsB = 0.0
  var totalScoreA = 0.0
  var totalScoreB = 0.0
  var totalRankA = 0.0
  var totalRankB = 0.0
  var seatCountA = 0
  var seatCountB = 0
  var totalTurns = 0.0

  mutating func merge(_ value: Aggregate) {
    combine(value)
  }

  mutating func combine(_ other: Aggregate) {
    winCreditsA += other.winCreditsA
    winCreditsB += other.winCreditsB
    totalScoreA += other.totalScoreA
    totalScoreB += other.totalScoreB
    totalRankA += other.totalRankA
    totalRankB += other.totalRankB
    seatCountA += other.seatCountA
    seatCountB += other.seatCountB
    totalTurns += other.totalTurns
  }
}

private actor EvaluationJobQueue {
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

private actor EvaluationProgressTracker {
  private let totalGames: Int
  private let startedAt: Date
  private let callback: (@Sendable (ModelEvaluationProgress) -> Void)?
  private let reportEvery: Int

  private var completed = 0
  private var lastReported = 0

  init(
    totalGames: Int,
    startedAt: Date,
    callback: (@Sendable (ModelEvaluationProgress) -> Void)?
  ) {
    self.totalGames = max(1, totalGames)
    self.startedAt = startedAt
    self.callback = callback
    self.reportEvery = max(1, totalGames / 100)
  }

  func record() {
    completed += 1
    guard let callback else { return }

    let shouldReport = completed == 1
      || completed == totalGames
      || (completed - lastReported) >= reportEvery
    guard shouldReport else { return }
    lastReported = completed

    let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
    let speed = Double(completed) / elapsed
    let remaining = max(0, totalGames - completed)
    let eta = speed > 0 ? Double(remaining) / speed : nil

    callback(
      ModelEvaluationProgress(
        completedGames: completed,
        totalGames: totalGames,
        elapsedSec: elapsed,
        gamesPerSec: speed,
        etaSec: eta
      )
    )
  }
}
