import Domain
import Foundation

public struct QuantizedDictionary: Codable, Hashable, Sendable {
  public var scale: Double
  public var values: [String: Int16]

  public init(scale: Double, values: [String: Int16]) {
    self.scale = scale
    self.values = values
  }
}

public struct QuantizedVector: Codable, Hashable, Sendable {
  public var scale: Double
  public var values: [Int16]

  public init(scale: Double, values: [Int16]) {
    self.scale = scale
    self.values = values
  }
}

public struct ExportedLinearValueModel: Codable, Hashable, Sendable {
  public var weights: QuantizedVector
  public var playerBiasById: QuantizedDictionary

  public init(weights: QuantizedVector, playerBiasById: QuantizedDictionary) {
    self.weights = weights
    self.playerBiasById = playerBiasById
  }
}

public struct ExportedPolicyValueModel: Codable, Hashable, Sendable {
  public static let formatVersion = 1

  public var formatVersion: Int
  public var createdAt: Date
  public var sourceModelSHA256: String
  public var sourceLabel: String
  public var policyBlend: Double
  public var valueBlend: Double
  public var passBias: Double
  public var actionBiasByKey: QuantizedDictionary
  public var pieceBiasById: QuantizedDictionary
  public var linearValueModel: ExportedLinearValueModel

  public init(
    formatVersion: Int = ExportedPolicyValueModel.formatVersion,
    createdAt: Date,
    sourceModelSHA256: String,
    sourceLabel: String,
    policyBlend: Double,
    valueBlend: Double,
    passBias: Double,
    actionBiasByKey: QuantizedDictionary,
    pieceBiasById: QuantizedDictionary,
    linearValueModel: ExportedLinearValueModel
  ) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.sourceModelSHA256 = sourceModelSHA256
    self.sourceLabel = sourceLabel
    self.policyBlend = policyBlend
    self.valueBlend = valueBlend
    self.passBias = passBias
    self.actionBiasByKey = actionBiasByKey
    self.pieceBiasById = pieceBiasById
    self.linearValueModel = linearValueModel
  }
}

public struct ModelExportManifest: Codable, Hashable, Sendable {
  public var exportedAt: Date
  public var sourceModelPath: String
  public var sourceModelSHA256: String
  public var sourceLabel: String
  public var formatVersion: Int

  public init(
    exportedAt: Date,
    sourceModelPath: String,
    sourceModelSHA256: String,
    sourceLabel: String,
    formatVersion: Int
  ) {
    self.exportedAt = exportedAt
    self.sourceModelPath = sourceModelPath
    self.sourceModelSHA256 = sourceModelSHA256
    self.sourceLabel = sourceLabel
    self.formatVersion = formatVersion
  }
}

public struct ModelExportPaths: Sendable {
  public var directory: URL
  public var inferenceModelPath: URL
  public var manifestPath: URL

  public init(directory: URL, inferenceModelPath: URL, manifestPath: URL) {
    self.directory = directory
    self.inferenceModelPath = inferenceModelPath
    self.manifestPath = manifestPath
  }
}

public enum ModelExporter {
  public static func export(
    sourceModel: TrainedPolicyValueModel,
    sourceModelData: Data,
    sourceModelPath: String,
    to directory: URL
  ) throws -> ModelExportPaths {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceHash = sourceModelData.sha256().hexString
    let exported = ExportedPolicyValueModel(
      createdAt: Date(),
      sourceModelSHA256: sourceHash,
      sourceLabel: sourceModel.label,
      policyBlend: sourceModel.policyBlend,
      valueBlend: sourceModel.valueBlend,
      passBias: sourceModel.passBias,
      actionBiasByKey: quantizeDictionary(sourceModel.actionBiasByKey),
      pieceBiasById: quantizeDictionary(sourceModel.pieceBiasById),
      linearValueModel: ExportedLinearValueModel(
        weights: quantizeVector([
          sourceModel.valueModel.intercept,
          sourceModel.valueModel.leadWeight,
          sourceModel.valueModel.progressWeight,
          sourceModel.valueModel.occupancyWeight,
        ]),
        playerBiasById: quantizeDictionary(sourceModel.valueModel.playerBiasById)
      )
    )

    let manifest = ModelExportManifest(
      exportedAt: Date(),
      sourceModelPath: sourceModelPath,
      sourceModelSHA256: sourceHash,
      sourceLabel: sourceModel.label,
      formatVersion: ExportedPolicyValueModel.formatVersion
    )

    let inferencePath = directory.appendingPathComponent("inference_model.json")
    let manifestPath = directory.appendingPathComponent("manifest.json")

    try write(exported, to: inferencePath)
    try write(manifest, to: manifestPath)

    return ModelExportPaths(
      directory: directory,
      inferenceModelPath: inferencePath,
      manifestPath: manifestPath
    )
  }

  private static func write<T: Encodable>(_ value: T, to path: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: path, options: [.atomic])
  }

  private static func quantizeDictionary(_ values: [String: Double]) -> QuantizedDictionary {
    guard !values.isEmpty else {
      return QuantizedDictionary(scale: 1, values: [:])
    }

    let maxAbs = max(1e-9, values.values.map { abs($0) }.max() ?? 1)
    let scale = maxAbs / 32767.0

    let quantized = Dictionary(uniqueKeysWithValues: values.map { key, value in
      let clipped = max(-32767.0, min(32767.0, (value / scale).rounded()))
      return (key, Int16(clipped))
    })

    return QuantizedDictionary(scale: scale, values: quantized)
  }

  private static func quantizeVector(_ values: [Double]) -> QuantizedVector {
    guard !values.isEmpty else {
      return QuantizedVector(scale: 1, values: [])
    }

    let maxAbs = max(1e-9, values.map { abs($0) }.max() ?? 1)
    let scale = maxAbs / 32767.0

    let quantized = values.map { value -> Int16 in
      let clipped = max(-32767.0, min(32767.0, (value / scale).rounded()))
      return Int16(clipped)
    }

    return QuantizedVector(scale: scale, values: quantized)
  }
}
