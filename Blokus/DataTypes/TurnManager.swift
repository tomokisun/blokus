import Foundation

/// 手番の進行を管理するためのヘルパー。
/// プレイヤーの順番を保持し、パス済みまたは全てのコマを使い切った
/// プレイヤーを自動的にスキップします。
struct TurnManager {
  private let order: [Player]
  private var currentIndex: Int?
  private var inactivePlayers: Set<Player> = []

  init(startingPlayer: Player = .red, order: [Player] = Player.allCases) {
    self.order = order
    if let index = order.firstIndex(of: startingPlayer) {
      currentIndex = index
    } else {
      currentIndex = order.isEmpty ? nil : 0
    }
  }

  var currentPlayer: Player? {
    guard let index = currentIndex, order.indices.contains(index) else { return nil }
    return order[index]
  }

  mutating func advance(after outcome: TurnOutcome) {
    guard let current = currentPlayer else { return }

    switch outcome {
    case let .placed(player, hasRemainingPieces):
      precondition(player == current, "Turn outcome must match the active player")
      if hasRemainingPieces {
        inactivePlayers.remove(player)
      } else {
        inactivePlayers.insert(player)
      }

    case let .passed(player):
      precondition(player == current, "Turn outcome must match the active player")
      inactivePlayers.insert(player)
    }

    currentIndex = nextActiveIndex(startingAfter: currentIndex)
  }

  private func nextActiveIndex(startingAfter index: Int?) -> Int? {
    guard !order.isEmpty else { return nil }

    let start = ((index ?? -1) + 1) % order.count
    var candidateIndex = start

    for _ in 0..<order.count {
      let candidate = order[candidateIndex]
      if !inactivePlayers.contains(candidate) {
        return candidateIndex
      }
      candidateIndex = (candidateIndex + 1) % order.count
    }

    return nil
  }
}

enum TurnOutcome {
  case placed(player: Player, hasRemainingPieces: Bool)
  case passed(player: Player)
}
