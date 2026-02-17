import Domain
import Foundation

public struct LearnedPolicyValuePredictor: PolicyValuePredicting {
  public var model: TrainedPolicyValueModel
  public var fallbackPredictor: HeuristicPolicyValuePredictor

  public init(
    model: TrainedPolicyValueModel,
    fallbackPredictor: HeuristicPolicyValuePredictor = HeuristicPolicyValuePredictor()
  ) {
    self.model = model
    self.fallbackPredictor = fallbackPredictor
  }

  public func predict(
    state: GameState,
    legalMoves: [CommandAction]
  ) -> PolicyValuePrediction {
    let fallback = fallbackPredictor.predict(state: state, legalMoves: legalMoves)
    let priors = buildPriors(legalMoves: legalMoves, fallbackPriors: fallback.priors)
    let values = buildValues(state: state, fallbackValues: fallback.values)
    return PolicyValuePrediction(priors: priors, values: values)
  }

  private func buildPriors(
    legalMoves: [CommandAction],
    fallbackPriors: [CommandAction: Double]
  ) -> [CommandAction: Double] {
    guard !legalMoves.isEmpty else { return [:] }

    let blend = max(0, min(1, model.policyBlend))
    let fallbackWeight = 1 - blend

    var logits: [CommandAction: Double] = [:]
    logits.reserveCapacity(legalMoves.count)

    for action in legalMoves {
      let fallbackPrior = max(1e-9, fallbackPriors[action] ?? (1.0 / Double(legalMoves.count)))
      let fallbackLogit = log(fallbackPrior)

      var learnedLogit = 0.0
      learnedLogit += model.actionBiasByKey[action.aiActionKey, default: 0]
      if let pieceId = action.placedPieceId {
        learnedLogit += model.pieceBiasById[pieceId, default: 0]
      }
      if action == .pass {
        learnedLogit += model.passBias
      }

      logits[action] = fallbackWeight * fallbackLogit + blend * learnedLogit
    }

    let stabilized = logits.values.max() ?? 0
    let expValues = logits.mapValues { exp($0 - stabilized) }
    let sumExp = max(1e-9, expValues.values.reduce(0, +))
    return expValues.mapValues { $0 / sumExp }
  }

  private func buildValues(
    state: GameState,
    fallbackValues: [PlayerID: Double]
  ) -> [PlayerID: Double] {
    let blend = max(0, min(1, model.valueBlend))
    let fallbackWeight = 1 - blend

    let counts = boardCounts(for: state)
    let totalCells = Double(max(1, BoardConstants.boardCellCount))
    let filledCells = counts.values.reduce(0, +)
    let progress = Double(filledCells) / totalCells
    let meanCount = Double(counts.values.reduce(0, +)) / Double(max(1, state.turnOrder.count))

    var values: [PlayerID: Double] = [:]
    values.reserveCapacity(state.turnOrder.count)

    for player in state.turnOrder {
      let occupied = Double(counts[player, default: 0])
      let lead = (occupied - meanCount) / totalCells
      let occupancyRatio = occupied / totalCells
      let learned = model.valueModel.predict(
        playerId: player,
        lead: lead,
        progress: progress,
        occupancyRatio: occupancyRatio
      )
      let fallback = fallbackValues[player, default: 0]
      let mixed = fallbackWeight * fallback + blend * learned
      values[player] = max(-1, min(1, mixed))
    }

    return values
  }

  private func boardCounts(for state: GameState) -> [PlayerID: Int] {
    var result: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: state.turnOrder.map { ($0, 0) })
    for cell in state.board.cells {
      guard let owner = cell else { continue }
      result[owner, default: 0] += 1
    }
    return result
  }
}
