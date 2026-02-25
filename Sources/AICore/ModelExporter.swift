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

public struct ExportedDenseLayer: Codable, Hashable, Sendable {
  public var weights: QuantizedVector
  public var bias: QuantizedVector
  public var inputSize: Int
  public var outputSize: Int

  public init(weights: QuantizedVector, bias: QuantizedVector, inputSize: Int, outputSize: Int) {
    self.weights = weights
    self.bias = bias
    self.inputSize = inputSize
    self.outputSize = outputSize
  }
}

public struct ExportedMLPValueModel: Codable, Hashable, Sendable {
  public var layers: [ExportedDenseLayer]
  public var inputSize: Int
  public var featureCount: Int

  public init(layers: [ExportedDenseLayer], inputSize: Int, featureCount: Int) {
    self.layers = layers
    self.inputSize = inputSize
    self.featureCount = featureCount
  }
}

public struct ExportedConv2DLayer: Codable, Hashable, Sendable {
  public var filters: QuantizedVector
  public var bias: QuantizedVector
  public var inChannels: Int
  public var outChannels: Int
  public var kernelSize: Int

  public init(
    filters: QuantizedVector, bias: QuantizedVector,
    inChannels: Int, outChannels: Int, kernelSize: Int
  ) {
    self.filters = filters
    self.bias = bias
    self.inChannels = inChannels
    self.outChannels = outChannels
    self.kernelSize = kernelSize
  }
}

public struct ExportedCNNValueModel: Codable, Hashable, Sendable {
  public var convLayers: [ExportedConv2DLayer]
  public var denseLayers: [ExportedDenseLayer]
  public var boardSize: Int
  public var inputChannels: Int

  public init(
    convLayers: [ExportedConv2DLayer], denseLayers: [ExportedDenseLayer],
    boardSize: Int, inputChannels: Int
  ) {
    self.convLayers = convLayers
    self.denseLayers = denseLayers
    self.boardSize = boardSize
    self.inputChannels = inputChannels
  }
}

public struct ExportedPolicyValueModel: Codable, Hashable, Sendable {
  public static let formatVersion = 2

  public var formatVersion: Int
  public var createdAt: Date
  public var sourceModelSHA256: String
  public var sourceLabel: String
  public var architecture: String
  public var policyBlend: Double
  public var valueBlend: Double
  public var passBias: Double
  public var actionBiasByKey: QuantizedDictionary
  public var pieceBiasById: QuantizedDictionary
  public var linearValueModel: ExportedLinearValueModel
  public var mlpValueModel: ExportedMLPValueModel?
  public var cnnValueModel: ExportedCNNValueModel?
  public var policyMLPModel: ExportedMLPValueModel?

  public init(
    formatVersion: Int = ExportedPolicyValueModel.formatVersion,
    createdAt: Date,
    sourceModelSHA256: String,
    sourceLabel: String,
    architecture: String = "linear",
    policyBlend: Double,
    valueBlend: Double,
    passBias: Double,
    actionBiasByKey: QuantizedDictionary,
    pieceBiasById: QuantizedDictionary,
    linearValueModel: ExportedLinearValueModel,
    mlpValueModel: ExportedMLPValueModel? = nil,
    cnnValueModel: ExportedCNNValueModel? = nil,
    policyMLPModel: ExportedMLPValueModel? = nil
  ) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.sourceModelSHA256 = sourceModelSHA256
    self.sourceLabel = sourceLabel
    self.architecture = architecture
    self.policyBlend = policyBlend
    self.valueBlend = valueBlend
    self.passBias = passBias
    self.actionBiasByKey = actionBiasByKey
    self.pieceBiasById = pieceBiasById
    self.linearValueModel = linearValueModel
    self.mlpValueModel = mlpValueModel
    self.cnnValueModel = cnnValueModel
    self.policyMLPModel = policyMLPModel
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
    let arch = sourceModel.resolvedArchitecture

    let exportedMLP: ExportedMLPValueModel? = sourceModel.mlpWeights.map { mlp in
      ExportedMLPValueModel(
        layers: mlp.layers.map { layer in
          ExportedDenseLayer(
            weights: quantizeVector(layer.weights),
            bias: quantizeVector(layer.bias),
            inputSize: layer.inputSize,
            outputSize: layer.outputSize
          )
        },
        inputSize: mlp.inputSize,
        featureCount: BoardFeatureExtractor.featureCount
      )
    }

    let exportedCNN: ExportedCNNValueModel? = sourceModel.cnnWeights.map { cnn in
      ExportedCNNValueModel(
        convLayers: cnn.convLayers.map { layer in
          ExportedConv2DLayer(
            filters: quantizeVector(layer.filters),
            bias: quantizeVector(layer.bias),
            inChannels: layer.inChannels,
            outChannels: layer.outChannels,
            kernelSize: layer.kernelSize
          )
        },
        denseLayers: cnn.denseLayers.map { layer in
          ExportedDenseLayer(
            weights: quantizeVector(layer.weights),
            bias: quantizeVector(layer.bias),
            inputSize: layer.inputSize,
            outputSize: layer.outputSize
          )
        },
        boardSize: cnn.boardSize,
        inputChannels: cnn.inputChannels
      )
    }

    let exported = ExportedPolicyValueModel(
      createdAt: Date(),
      sourceModelSHA256: sourceHash,
      sourceLabel: sourceModel.label,
      architecture: arch,
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
      ),
      mlpValueModel: exportedMLP,
      cnnValueModel: exportedCNN,
      policyMLPModel: sourceModel.policyMLPWeights.map { policyMLP in
        ExportedMLPValueModel(
          layers: policyMLP.layers.map { layer in
            ExportedDenseLayer(
              weights: quantizeVector(layer.weights),
              bias: quantizeVector(layer.bias),
              inputSize: layer.inputSize,
              outputSize: layer.outputSize
            )
          },
          inputSize: policyMLP.inputSize,
          featureCount: MoveFeatureExtractor.featureCount
        )
      }
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
