import Domain
import Foundation

public struct PolicyValuePrediction: Sendable {
  public var priors: [CommandAction: Double]
  public var values: [PlayerID: Double]

  public init(priors: [CommandAction: Double], values: [PlayerID: Double]) {
    self.priors = priors
    self.values = values
  }
}

public protocol PolicyValuePredicting: Sendable {
  func predict(
    state: GameState,
    legalMoves: [CommandAction]
  ) -> PolicyValuePrediction
}

public struct HeuristicPolicyValuePredictor: PolicyValuePredicting {
  private static let pieceCellCounts: [String: Int] = {
    Dictionary(uniqueKeysWithValues: PieceLibrary.pieces.map { ($0.id, $0.baseCells.count) })
  }()

  public init() {}

  public func predict(
    state: GameState,
    legalMoves: [CommandAction]
  ) -> PolicyValuePrediction {
    PolicyValuePrediction(
      priors: buildPriors(for: legalMoves),
      values: evaluatePlayers(state: state)
    )
  }

  private func buildPriors(for legalMoves: [CommandAction]) -> [CommandAction: Double] {
    guard !legalMoves.isEmpty else { return [:] }

    let center = Double(BoardConstants.maxBoardIndex) / 2.0
    var raw: [CommandAction: Double] = [:]
    raw.reserveCapacity(legalMoves.count)

    for action in legalMoves {
      switch action {
      case .pass:
        raw[action] = 0.01

      case let .place(pieceId, _, origin):
        let pieceSize = Double(Self.pieceCellCounts[pieceId, default: 1])
        let distance = abs(Double(origin.x) - center) + abs(Double(origin.y) - center)
        let centrality = max(0, 20 - distance) / 20
        raw[action] = pieceSize * 1.5 + centrality
      }
    }

    let sum = max(1e-9, raw.values.reduce(0, +))
    return raw.mapValues { $0 / sum }
  }

  private func evaluatePlayers(state: GameState) -> [PlayerID: Double] {
    var occupiedCounts: [PlayerID: Int] = [:]
    occupiedCounts.reserveCapacity(state.turnOrder.count)
    for cell in state.board.cells {
      guard let player = cell else { continue }
      occupiedCounts[player, default: 0] += 1
    }

    var raw: [PlayerID: Double] = [:]
    raw.reserveCapacity(state.turnOrder.count)

    for player in state.turnOrder {
      let occupied = Double(occupiedCounts[player, default: 0])
      let remainingCells = Double(
        state.remainingPieces[player, default: []]
          .reduce(0) { partial, pieceId in
            partial + Self.pieceCellCounts[pieceId, default: 1]
          }
      )

      var score = occupied - remainingCells * 0.15
      if player == state.activePlayerId, !state.hasAnyLegalMove(for: player) {
        score -= 5
      }
      raw[player] = score
    }

    let mean = raw.values.reduce(0, +) / Double(max(1, raw.count))
    let scale = max(
      1,
      raw.values
        .map { abs($0 - mean) }
        .max() ?? 1
    )

    return raw.mapValues { value in
      let normalized = (value - mean) / scale
      return max(-1, min(1, normalized))
    }
  }
}
