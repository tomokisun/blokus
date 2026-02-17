import Domain
import Foundation

public struct LinearValueModel: Codable, Hashable, Sendable {
  public var intercept: Double
  public var leadWeight: Double
  public var progressWeight: Double
  public var occupancyWeight: Double
  public var playerBiasById: [String: Double]

  public init(
    intercept: Double,
    leadWeight: Double,
    progressWeight: Double,
    occupancyWeight: Double,
    playerBiasById: [String: Double]
  ) {
    self.intercept = intercept
    self.leadWeight = leadWeight
    self.progressWeight = progressWeight
    self.occupancyWeight = occupancyWeight
    self.playerBiasById = playerBiasById
  }
}

public struct ModelTrainingMetrics: Codable, Hashable, Sendable {
  public var positionCount: Int
  public var uniqueActionCount: Int
  public var storedActionBiasCount: Int
  public var uniquePieceCount: Int
  public var valueMSE: Double
  public var averageTarget: Double

  public init(
    positionCount: Int,
    uniqueActionCount: Int,
    storedActionBiasCount: Int,
    uniquePieceCount: Int,
    valueMSE: Double,
    averageTarget: Double
  ) {
    self.positionCount = positionCount
    self.uniqueActionCount = uniqueActionCount
    self.storedActionBiasCount = storedActionBiasCount
    self.uniquePieceCount = uniquePieceCount
    self.valueMSE = valueMSE
    self.averageTarget = averageTarget
  }
}

public struct TrainedPolicyValueModel: Codable, Hashable, Sendable {
  public static let formatVersion = 1

  public var formatVersion: Int
  public var createdAt: Date
  public var label: String
  public var policyBlend: Double
  public var valueBlend: Double
  public var passBias: Double
  public var actionBiasByKey: [String: Double]
  public var pieceBiasById: [String: Double]
  public var valueModel: LinearValueModel
  public var metrics: ModelTrainingMetrics

  public init(
    formatVersion: Int = TrainedPolicyValueModel.formatVersion,
    createdAt: Date,
    label: String,
    policyBlend: Double,
    valueBlend: Double,
    passBias: Double,
    actionBiasByKey: [String: Double],
    pieceBiasById: [String: Double],
    valueModel: LinearValueModel,
    metrics: ModelTrainingMetrics
  ) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.label = label
    self.policyBlend = policyBlend
    self.valueBlend = valueBlend
    self.passBias = passBias
    self.actionBiasByKey = actionBiasByKey
    self.pieceBiasById = pieceBiasById
    self.valueModel = valueModel
    self.metrics = metrics
  }
}

public struct TrainerConfiguration: Hashable, Sendable {
  public var label: String
  public var policyBlend: Double
  public var valueBlend: Double
  public var selectedActionBoost: Double
  public var maxActionBiasCount: Int
  public var ridgeLambda: Double

  public init(
    label: String,
    policyBlend: Double = 0.65,
    valueBlend: Double = 0.7,
    selectedActionBoost: Double = 1.0,
    maxActionBiasCount: Int = 40000,
    ridgeLambda: Double = 1e-3
  ) {
    self.label = label
    self.policyBlend = max(0, min(1, policyBlend))
    self.valueBlend = max(0, min(1, valueBlend))
    self.selectedActionBoost = max(0, selectedActionBoost)
    self.maxActionBiasCount = max(1, maxActionBiasCount)
    self.ridgeLambda = max(0, ridgeLambda)
  }
}

public struct ModelTrainingResult: Sendable {
  public var model: TrainedPolicyValueModel

  public init(model: TrainedPolicyValueModel) {
    self.model = model
  }
}

public enum TrainingDatasetReader {
  public static func resolvePositionsFile(from path: URL) -> URL {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue {
      return path.appendingPathComponent("positions.ndjson")
    }
    return path
  }

  public static func loadPositions(
    from path: URL,
    limit: Int? = nil,
    progress: ((Int) -> Void)? = nil
  ) throws -> [TrainingPosition] {
    let positionsFile = resolvePositionsFile(from: path)
    let data = try Data(contentsOf: positionsFile)
    guard let text = String(data: data, encoding: .utf8) else {
      throw NSError(domain: "TrainingDatasetReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "positions.ndjson のUTF-8デコードに失敗しました"])
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var positions: [TrainingPosition] = []
    let cappedLimit = limit.map { max(0, $0) }
    positions.reserveCapacity(min(cappedLimit ?? 50000, 200000))

    var loaded = 0
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
      if let cappedLimit, loaded >= cappedLimit {
        break
      }
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty { continue }

      do {
        let position = try decoder.decode(TrainingPosition.self, from: Data(line.utf8))
        positions.append(position)
        loaded += 1
        if loaded == 1 || loaded % 10000 == 0 {
          progress?(loaded)
        }
      } catch {
        throw NSError(
          domain: "TrainingDatasetReader",
          code: 2,
          userInfo: [
            NSLocalizedDescriptionKey: "positions.ndjson のデコードに失敗しました (line: \(loaded + 1))",
            NSUnderlyingErrorKey: error,
          ]
        )
      }
    }

    if loaded > 0 {
      progress?(loaded)
    }
    return positions
  }
}

public enum TrainedModelIO {
  public static func save(_ model: TrainedPolicyValueModel, to path: URL) throws {
    let parent = path.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(model)
    try data.write(to: path, options: [.atomic])
  }

  public static func load(from path: URL) throws -> TrainedPolicyValueModel {
    let data = try Data(contentsOf: path)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TrainedPolicyValueModel.self, from: data)
  }
}

public enum PolicyValueModelTrainer {
  public static func train(
    positions: [TrainingPosition],
    configuration: TrainerConfiguration
  ) -> ModelTrainingResult {
    guard !positions.isEmpty else {
      let emptyModel = TrainedPolicyValueModel(
        createdAt: Date(),
        label: configuration.label,
        policyBlend: configuration.policyBlend,
        valueBlend: configuration.valueBlend,
        passBias: 0,
        actionBiasByKey: [:],
        pieceBiasById: [:],
        valueModel: LinearValueModel(
          intercept: 0,
          leadWeight: 0,
          progressWeight: 0,
          occupancyWeight: 0,
          playerBiasById: [:]
        ),
        metrics: ModelTrainingMetrics(
          positionCount: 0,
          uniqueActionCount: 0,
          storedActionBiasCount: 0,
          uniquePieceCount: 0,
          valueMSE: 0,
          averageTarget: 0
        )
      )
      return ModelTrainingResult(model: emptyModel)
    }

    var actionMass: [String: Double] = [:]
    var pieceMass: [String: Double] = [:]
    var selectedCountByAction: [String: Double] = [:]

    var playerTargetSum: [String: Double] = [:]
    var playerTargetCount: [String: Int] = [:]

    var xtx = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
    var xty = Array(repeating: 0.0, count: 4)

    var targetSum = 0.0
    var targetCount = 0

    for position in positions {
      for entry in position.policy {
        actionMass[entry.actionKey, default: 0] += max(0, entry.probability)
        if let pieceId = entry.action.placedPieceId {
          pieceMass[pieceId, default: 0] += max(0, entry.probability)
        }
      }

      selectedCountByAction[position.selectedActionKey, default: 0] += configuration.selectedActionBoost
      if let pieceId = position.selectedAction.placedPieceId {
        pieceMass[pieceId, default: 0] += configuration.selectedActionBoost
      }

      let activeTarget = position.outcomeByPlayer.first { $0.playerId == position.activePlayer }?.value ?? 0
      targetSum += activeTarget
      targetCount += 1

      playerTargetSum[position.activePlayer.rawValue, default: 0] += activeTarget
      playerTargetCount[position.activePlayer.rawValue, default: 0] += 1

      let feature = FeatureExtractor.extract(from: position)
      let x = [1.0, feature.lead, feature.progress, feature.occupancyRatio]
      accumulateNormalEquation(xtx: &xtx, xty: &xty, x: x, y: activeTarget)
    }

    for (actionKey, boostedCount) in selectedCountByAction {
      actionMass[actionKey, default: 0] += boostedCount
    }

    var ridgeXtx = xtx
    for i in 0..<4 {
      ridgeXtx[i][i] += configuration.ridgeLambda
    }
    let weights = solveLinearSystem(xtx: ridgeXtx, xty: xty)

    let actionBiasByKey = buildActionBiases(
      actionMass: actionMass,
      maxCount: configuration.maxActionBiasCount
    )
    let pieceBiasById = buildBiases(from: pieceMass)
    let passBias = actionBiasByKey[CommandAction.pass.aiActionKey] ?? 0

    let playerBiasById = Dictionary(uniqueKeysWithValues: playerTargetSum.map { key, sum in
      let count = max(1, playerTargetCount[key] ?? 1)
      return (key, sum / Double(count))
    })

    let valueModel = LinearValueModel(
      intercept: weights[0],
      leadWeight: weights[1],
      progressWeight: weights[2],
      occupancyWeight: weights[3],
      playerBiasById: playerBiasById
    )

    let mse = computeValueMSE(positions: positions, valueModel: valueModel)
    let metrics = ModelTrainingMetrics(
      positionCount: positions.count,
      uniqueActionCount: actionMass.count,
      storedActionBiasCount: actionBiasByKey.count,
      uniquePieceCount: pieceBiasById.count,
      valueMSE: mse,
      averageTarget: targetCount > 0 ? targetSum / Double(targetCount) : 0
    )

    let model = TrainedPolicyValueModel(
      createdAt: Date(),
      label: configuration.label,
      policyBlend: configuration.policyBlend,
      valueBlend: configuration.valueBlend,
      passBias: passBias,
      actionBiasByKey: actionBiasByKey,
      pieceBiasById: pieceBiasById,
      valueModel: valueModel,
      metrics: metrics
    )

    return ModelTrainingResult(model: model)
  }

  private static func buildActionBiases(
    actionMass: [String: Double],
    maxCount: Int
  ) -> [String: Double] {
    guard !actionMass.isEmpty else { return [:] }

    let totalMass = max(1e-9, actionMass.values.reduce(0, +))
    let averageMass = totalMass / Double(max(1, actionMass.count))
    let alpha = 1e-6

    let sorted = actionMass
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          return lhs.key < rhs.key
        }
        return lhs.value > rhs.value
      }
      .prefix(maxCount)

    var result: [String: Double] = [:]
    result.reserveCapacity(sorted.count)

    for (key, mass) in sorted {
      let bias = log((mass + alpha) / (averageMass + alpha))
      result[key] = bias
    }
    return result
  }

  private static func buildBiases(from mass: [String: Double]) -> [String: Double] {
    guard !mass.isEmpty else { return [:] }

    let total = max(1e-9, mass.values.reduce(0, +))
    let avg = total / Double(max(1, mass.count))
    let alpha = 1e-6

    return Dictionary(uniqueKeysWithValues: mass.map { key, value in
      (key, log((value + alpha) / (avg + alpha)))
    })
  }

  private static func computeValueMSE(
    positions: [TrainingPosition],
    valueModel: LinearValueModel
  ) -> Double {
    guard !positions.isEmpty else { return 0 }

    var sumSquaredError = 0.0
    var count = 0
    for position in positions {
      let target = position.outcomeByPlayer.first(where: { $0.playerId == position.activePlayer })?.value ?? 0
      let feature = FeatureExtractor.extract(from: position)
      let prediction = valueModel.predict(
        playerId: position.activePlayer,
        lead: feature.lead,
        progress: feature.progress,
        occupancyRatio: feature.occupancyRatio
      )
      let diff = prediction - target
      sumSquaredError += diff * diff
      count += 1
    }

    return count > 0 ? sumSquaredError / Double(count) : 0
  }

  private static func accumulateNormalEquation(
    xtx: inout [[Double]],
    xty: inout [Double],
    x: [Double],
    y: Double
  ) {
    for i in 0..<x.count {
      xty[i] += x[i] * y
      for j in 0..<x.count {
        xtx[i][j] += x[i] * x[j]
      }
    }
  }

  private static func solveLinearSystem(xtx: [[Double]], xty: [Double]) -> [Double] {
    let n = xty.count
    guard n > 0 else { return [] }

    var a = xtx
    var b = xty

    for i in 0..<n {
      var pivot = i
      var maxValue = abs(a[i][i])
      for row in (i + 1)..<n {
        let value = abs(a[row][i])
        if value > maxValue {
          maxValue = value
          pivot = row
        }
      }

      if maxValue < 1e-12 {
        continue
      }

      if pivot != i {
        a.swapAt(i, pivot)
        b.swapAt(i, pivot)
      }

      let divisor = a[i][i]
      if abs(divisor) < 1e-12 {
        continue
      }

      for col in i..<n {
        a[i][col] /= divisor
      }
      b[i] /= divisor

      for row in 0..<n where row != i {
        let factor = a[row][i]
        if abs(factor) < 1e-12 { continue }
        for col in i..<n {
          a[row][col] -= factor * a[i][col]
        }
        b[row] -= factor * b[i]
      }
    }

    return b
  }
}

private struct FeatureExtractor {
  var lead: Double
  var progress: Double
  var occupancyRatio: Double

  static func extract(from position: TrainingPosition) -> FeatureExtractor {
    let totalCells = Double(max(1, BoardConstants.boardCellCount))

    var countsByPlayerId: [String: Int] = [:]
    var filled = 0

    for marker in position.boardEncoding {
      guard marker > 0 else { continue }
      filled += 1
      let index = Int(marker) - 1
      guard index >= 0, index < PlayerID.allCases.count else { continue }
      let playerId = PlayerID.allCases[index]
      countsByPlayerId[playerId.rawValue, default: 0] += 1
    }

    let activeCount = Double(countsByPlayerId[position.activePlayer.rawValue, default: 0])
    let participantCount = max(1, position.outcomeByPlayer.count)
    let sumCounts = position.outcomeByPlayer.reduce(0.0) { partial, item in
      partial + Double(countsByPlayerId[item.playerId.rawValue, default: 0])
    }
    let meanCount = sumCounts / Double(participantCount)

    return FeatureExtractor(
      lead: (activeCount - meanCount) / totalCells,
      progress: Double(filled) / totalCells,
      occupancyRatio: activeCount / totalCells
    )
  }
}

public extension LinearValueModel {
  func predict(
    playerId: PlayerID,
    lead: Double,
    progress: Double,
    occupancyRatio: Double
  ) -> Double {
    let playerBias = playerBiasById[playerId.rawValue, default: 0]
    let raw = intercept
      + leadWeight * lead
      + progressWeight * progress
      + occupancyWeight * occupancyRatio
      + playerBias
    return max(-1, min(1, raw))
  }
}

public extension CommandAction {
  var placedPieceId: String? {
    switch self {
    case let .place(pieceId, _, _):
      return pieceId
    case .pass:
      return nil
    }
  }
}
