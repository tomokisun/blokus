import Domain
import Foundation

public struct MCTSConfiguration: Codable, Hashable, Sendable {
  public var simulations: Int
  public var explorationConstant: Double
  public var maxCandidateMoves: Int
  public var temperature: Double

  public init(
    simulations: Int = 300,
    explorationConstant: Double = 1.25,
    maxCandidateMoves: Int = 48,
    temperature: Double = 0
  ) {
    self.simulations = simulations
    self.explorationConstant = explorationConstant
    self.maxCandidateMoves = maxCandidateMoves
    self.temperature = temperature
  }
}

public struct MCTSDecision: Sendable {
  public var selectedAction: CommandAction
  public var policy: [MovePolicyEntry]
  public var rootValues: [PlayerValue]

  public init(
    selectedAction: CommandAction,
    policy: [MovePolicyEntry],
    rootValues: [PlayerValue]
  ) {
    self.selectedAction = selectedAction
    self.policy = policy
    self.rootValues = rootValues
  }
}

public struct MCTSAgent<Model: PolicyValuePredicting>: Sendable {
  private final class Node {
    let toPlay: PlayerID
    let legalMoves: [CommandAction]
    let priors: [CommandAction: Double]
    var visitCount: Int
    var valueSums: [PlayerID: Double]
    var children: [CommandAction: Node]

    init(
      toPlay: PlayerID,
      legalMoves: [CommandAction],
      priors: [CommandAction: Double]
    ) {
      self.toPlay = toPlay
      self.legalMoves = legalMoves
      self.priors = priors
      self.visitCount = 0
      self.valueSums = [:]
      self.children = [:]
    }
  }

  private let predictor: Model
  private let moveGenerator: LegalMoveGenerator
  private let config: MCTSConfiguration

  public init(
    predictor: Model,
    moveGenerator: LegalMoveGenerator = LegalMoveGenerator(),
    config: MCTSConfiguration = MCTSConfiguration()
  ) {
    self.predictor = predictor
    self.moveGenerator = moveGenerator
    self.config = config
  }

  public func decide<R: RandomNumberGenerator>(
    state: GameState,
    rng: inout R
  ) -> MCTSDecision {
    let rootPlayer = state.activePlayerId
    let rootLegal = moveGenerator.legalMoves(
      for: state,
      playerId: rootPlayer,
      maxCount: max(1, config.maxCandidateMoves)
    )

    guard !rootLegal.isEmpty else {
      return MCTSDecision(
        selectedAction: .pass,
        policy: [MovePolicyEntry(action: .pass, probability: 1)],
        rootValues: state.turnOrder.map { PlayerValue(playerId: $0, value: 0) }
      )
    }

    let rootPrediction = predictor.predict(state: state, legalMoves: rootLegal)
    let root = Node(
      toPlay: rootPlayer,
      legalMoves: rootLegal,
      priors: Self.normalizedPriors(for: rootLegal, from: rootPrediction.priors)
    )

    let simulations = max(1, config.simulations)
    for _ in 0..<simulations {
      var simulationState = state
      var path: [Node] = [root]
      var node = root
      var leafValues: [PlayerID: Double] = [:]

      while true {
        if simulationState.phase == .finished {
          leafValues = terminalValues(for: simulationState)
          break
        }

        guard let selectedAction = selectAction(from: node, rng: &rng) else {
          leafValues = terminalValues(for: simulationState)
          break
        }

        let currentPlayer = simulationState.activePlayerId
        guard simulationState.apply(action: selectedAction, by: currentPlayer) == nil else {
          leafValues = terminalValues(for: simulationState)
          break
        }

        if let child = node.children[selectedAction] {
          node = child
          path.append(child)
          continue
        }

        let childLegalMoves = moveGenerator.legalMoves(
          for: simulationState,
          playerId: simulationState.activePlayerId,
          maxCount: max(1, config.maxCandidateMoves)
        )
        let childPrediction = predictor.predict(
          state: simulationState,
          legalMoves: childLegalMoves
        )

        let child = Node(
          toPlay: simulationState.activePlayerId,
          legalMoves: childLegalMoves,
          priors: Self.normalizedPriors(for: childLegalMoves, from: childPrediction.priors)
        )
        node.children[selectedAction] = child
        node = child
        path.append(child)
        leafValues = childPrediction.values
        break
      }

      backpropagate(path: path, values: leafValues, players: state.turnOrder)
    }

    let policy = buildRootPolicy(root: root)
    let selectedAction = selectActionFromRootPolicy(policy, rng: &rng)
    let rootValues: [PlayerValue]
    if root.visitCount == 0 {
      rootValues = state.turnOrder.map {
        PlayerValue(playerId: $0, value: rootPrediction.values[$0, default: 0])
      }
    } else {
      rootValues = state.turnOrder.map {
        PlayerValue(
          playerId: $0,
          value: root.valueSums[$0, default: 0] / Double(max(1, root.visitCount))
        )
      }
    }

    return MCTSDecision(
      selectedAction: selectedAction,
      policy: policy,
      rootValues: rootValues
    )
  }

  private static func normalizedPriors(
    for legalMoves: [CommandAction],
    from raw: [CommandAction: Double]
  ) -> [CommandAction: Double] {
    guard !legalMoves.isEmpty else { return [:] }

    var priors: [CommandAction: Double] = [:]
    let uniform = 1.0 / Double(legalMoves.count)
    var sum = 0.0

    for action in legalMoves {
      let value = max(0, raw[action] ?? uniform)
      priors[action] = value
      sum += value
    }

    if sum <= 1e-12 {
      return Dictionary(uniqueKeysWithValues: legalMoves.map { ($0, uniform) })
    }

    return priors.mapValues { $0 / sum }
  }

  private func selectAction<R: RandomNumberGenerator>(
    from node: Node,
    rng: inout R
  ) -> CommandAction? {
    guard !node.legalMoves.isEmpty else { return nil }

    var bestScore = -Double.infinity
    var bestActions: [CommandAction] = []

    let parentVisits = Double(max(1, node.visitCount))
    for action in node.legalMoves {
      let child = node.children[action]
      let childVisits = Double(child?.visitCount ?? 0)
      let prior = node.priors[action] ?? (1.0 / Double(max(1, node.legalMoves.count)))
      let qValue: Double
      if let child, child.visitCount > 0 {
        qValue = child.valueSums[node.toPlay, default: 0] / Double(child.visitCount)
      } else {
        qValue = 0
      }
      let uValue = config.explorationConstant * prior * sqrt(parentVisits) / (1 + childVisits)
      let score = qValue + uValue

      if score > bestScore + 1e-12 {
        bestScore = score
        bestActions = [action]
      } else if abs(score - bestScore) <= 1e-12 {
        bestActions.append(action)
      }
    }

    if bestActions.count == 1 {
      return bestActions[0]
    }
    let index = Int(rng.next() % UInt64(max(1, bestActions.count)))
    return bestActions[index]
  }

  private func backpropagate(
    path: [Node],
    values: [PlayerID: Double],
    players: [PlayerID]
  ) {
    for node in path {
      node.visitCount += 1
      for player in players {
        node.valueSums[player, default: 0] += values[player, default: 0]
      }
    }
  }

  private func buildRootPolicy(root: Node) -> [MovePolicyEntry] {
    guard !root.legalMoves.isEmpty else {
      return [MovePolicyEntry(action: .pass, probability: 1)]
    }

    let totalVisits = root.legalMoves.reduce(0) { partial, action in
      partial + (root.children[action]?.visitCount ?? 0)
    }

    if totalVisits == 0 {
      let uniform = 1.0 / Double(root.legalMoves.count)
      return root.legalMoves.map { MovePolicyEntry(action: $0, probability: uniform) }
    }

    return root.legalMoves.map { action in
      let visits = root.children[action]?.visitCount ?? 0
      return MovePolicyEntry(
        action: action,
        probability: Double(visits) / Double(totalVisits)
      )
    }
  }

  private func selectActionFromRootPolicy<R: RandomNumberGenerator>(
    _ policy: [MovePolicyEntry],
    rng: inout R
  ) -> CommandAction {
    guard !policy.isEmpty else { return .pass }

    if config.temperature <= 0 {
      return policy.max { lhs, rhs in lhs.probability < rhs.probability }?.action ?? .pass
    }

    let exponent = 1.0 / config.temperature
    let weighted = policy.map { entry in
      (entry.action, pow(max(1e-9, entry.probability), exponent))
    }
    let total = weighted.reduce(0.0) { $0 + $1.1 }
    if total <= 1e-12 {
      return policy.max { lhs, rhs in lhs.probability < rhs.probability }?.action ?? .pass
    }

    var threshold = rng.nextUnitDouble() * total
    for (action, value) in weighted {
      threshold -= value
      if threshold <= 0 {
        return action
      }
    }

    return weighted.last?.0 ?? .pass
  }

  private func terminalValues(for state: GameState) -> [PlayerID: Double] {
    var counts: [PlayerID: Int] = [:]
    counts.reserveCapacity(state.turnOrder.count)
    for cell in state.board.cells {
      guard let owner = cell else { continue }
      counts[owner, default: 0] += 1
    }

    let average = Double(counts.values.reduce(0, +)) / Double(max(1, state.turnOrder.count))
    let scale = Double(max(1, BoardConstants.boardCellCount))

    var values: [PlayerID: Double] = [:]
    for player in state.turnOrder {
      let score = Double(counts[player, default: 0])
      values[player] = max(-1, min(1, (score - average) / scale))
    }
    return values
  }
}
