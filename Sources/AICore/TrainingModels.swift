import Domain
import Foundation

public struct SelfPlayConfiguration: Codable, Hashable, Sendable {
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

public struct MovePolicyEntry: Codable, Hashable, Sendable {
  public var action: CommandAction
  public var actionKey: String
  public var probability: Double

  public init(action: CommandAction, probability: Double) {
    self.action = action
    self.actionKey = action.aiActionKey
    self.probability = probability
  }
}

public struct PlayerValue: Codable, Hashable, Sendable {
  public var playerId: PlayerID
  public var value: Double

  public init(playerId: PlayerID, value: Double) {
    self.playerId = playerId
    self.value = value
  }
}

public struct TrainingPosition: Codable, Hashable, Sendable {
  public var gameId: GameID
  public var ply: Int
  public var activePlayer: PlayerID
  public var boardEncoding: [UInt8]
  public var selectedAction: CommandAction
  public var selectedActionKey: String
  public var policy: [MovePolicyEntry]
  public var outcomeByPlayer: [PlayerValue]

  public init(
    gameId: GameID,
    ply: Int,
    activePlayer: PlayerID,
    boardEncoding: [UInt8],
    selectedAction: CommandAction,
    policy: [MovePolicyEntry],
    outcomeByPlayer: [PlayerValue]
  ) {
    self.gameId = gameId
    self.ply = ply
    self.activePlayer = activePlayer
    self.boardEncoding = boardEncoding
    self.selectedAction = selectedAction
    self.selectedActionKey = selectedAction.aiActionKey
    self.policy = policy
    self.outcomeByPlayer = outcomeByPlayer
  }
}

public struct SelfPlayGameSummary: Codable, Hashable, Sendable {
  public var gameId: GameID
  public var turns: Int
  public var winnerIds: [PlayerID]
  public var scores: [PlayerValue]

  public init(gameId: GameID, turns: Int, winnerIds: [PlayerID], scores: [PlayerValue]) {
    self.gameId = gameId
    self.turns = turns
    self.winnerIds = winnerIds
    self.scores = scores
  }
}

public struct SelfPlayGameRecord: Codable, Hashable, Sendable {
  public var summary: SelfPlayGameSummary
  public var positions: [TrainingPosition]

  public init(summary: SelfPlayGameSummary, positions: [TrainingPosition]) {
    self.summary = summary
    self.positions = positions
  }
}

public struct SelfPlayBatchResult: Codable, Sendable {
  public var configuration: SelfPlayConfiguration
  public var startedAt: Date
  public var finishedAt: Date
  public var games: [SelfPlayGameSummary]
  public var positions: [TrainingPosition]

  public init(
    configuration: SelfPlayConfiguration,
    startedAt: Date,
    finishedAt: Date,
    games: [SelfPlayGameSummary],
    positions: [TrainingPosition]
  ) {
    self.configuration = configuration
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.games = games
    self.positions = positions
  }
}

public struct SelfPlayProgress: Sendable {
  public var completedGames: Int
  public var totalGames: Int
  public var generatedPositions: Int
  public var elapsedSec: TimeInterval
  public var gamesPerSec: Double
  public var etaSec: TimeInterval?

  public init(
    completedGames: Int,
    totalGames: Int,
    generatedPositions: Int,
    elapsedSec: TimeInterval,
    gamesPerSec: Double,
    etaSec: TimeInterval?
  ) {
    self.completedGames = completedGames
    self.totalGames = totalGames
    self.generatedPositions = generatedPositions
    self.elapsedSec = elapsedSec
    self.gamesPerSec = gamesPerSec
    self.etaSec = etaSec
  }
}

public enum TrainingEncoding {
  public static func encodeBoard(_ state: GameState) -> [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(state.board.cells.count)
    for value in state.board.cells {
      guard let playerId = value,
            let index = state.turnOrder.firstIndex(of: playerId) else {
        result.append(0)
        continue
      }
      result.append(UInt8(index + 1))
    }
    return result
  }
}

public extension CommandAction {
  var aiActionKey: String {
    switch self {
    case let .place(pieceId, variantId, origin):
      return "P|\(pieceId)|\(variantId)|\(origin.x)|\(origin.y)"
    case .pass:
      return "PASS"
    }
  }
}
