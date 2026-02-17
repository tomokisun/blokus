import AICore
import Domain
import Foundation
import Testing

extension AppBaseSuite {
  @Test
  func trainAndExportPipelineSmoke() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TrainingPipeline-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let positionsPath = tempDir.appendingPathComponent("positions.ndjson")
    try writePositions(makeSyntheticPositions(), to: positionsPath)

    let loaded = try TrainingDatasetReader.loadPositions(from: positionsPath, limit: nil, progress: nil)
    #expect(loaded.count == 3)

    let trainResult = PolicyValueModelTrainer.train(
      positions: loaded,
      configuration: TrainerConfiguration(
        label: "test-model",
        policyBlend: 0.6,
        valueBlend: 0.7,
        selectedActionBoost: 1,
        maxActionBiasCount: 32,
        ridgeLambda: 1e-3
      )
    )

    #expect(trainResult.model.metrics.positionCount == 3)
    #expect(!trainResult.model.pieceBiasById.isEmpty)

    let modelPath = tempDir.appendingPathComponent("model.json")
    try TrainedModelIO.save(trainResult.model, to: modelPath)
    let loadedModel = try TrainedModelIO.load(from: modelPath)
    #expect(loadedModel.label == "test-model")

    let exported = try ModelExporter.export(
      sourceModel: loadedModel,
      sourceModelData: try Data(contentsOf: modelPath),
      sourceModelPath: modelPath.path,
      to: tempDir.appendingPathComponent("export", isDirectory: true)
    )

    #expect(FileManager.default.fileExists(atPath: exported.inferenceModelPath.path))
    #expect(FileManager.default.fileExists(atPath: exported.manifestPath.path))
  }
}

private func makeSyntheticPositions() -> [TrainingPosition] {
  var boardA = Array(repeating: UInt8(0), count: BoardConstants.boardCellCount)
  boardA[0] = 1

  var boardB = Array(repeating: UInt8(0), count: BoardConstants.boardCellCount)
  boardB[0] = 1
  boardB[1] = 2

  var boardC = Array(repeating: UInt8(0), count: BoardConstants.boardCellCount)
  boardC[0] = 1
  boardC[20] = 1
  boardC[399] = 2

  return [
    TrainingPosition(
      gameId: "G-1",
      ply: 0,
      activePlayer: .blue,
      boardEncoding: boardA,
      selectedAction: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)),
      policy: [
        MovePolicyEntry(action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)), probability: 0.9),
        MovePolicyEntry(action: .pass, probability: 0.1),
      ],
      outcomeByPlayer: [
        PlayerValue(playerId: .blue, value: 0.6),
        PlayerValue(playerId: .yellow, value: -0.6),
      ]
    ),
    TrainingPosition(
      gameId: "G-1",
      ply: 1,
      activePlayer: .yellow,
      boardEncoding: boardB,
      selectedAction: .place(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 1, y: 1)),
      policy: [
        MovePolicyEntry(action: .place(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 1, y: 1)), probability: 0.8),
        MovePolicyEntry(action: .pass, probability: 0.2),
      ],
      outcomeByPlayer: [
        PlayerValue(playerId: .blue, value: 0.3),
        PlayerValue(playerId: .yellow, value: -0.3),
      ]
    ),
    TrainingPosition(
      gameId: "G-2",
      ply: 3,
      activePlayer: .blue,
      boardEncoding: boardC,
      selectedAction: .place(pieceId: "tri-3", variantId: 0, origin: BoardPoint(x: 2, y: 2)),
      policy: [
        MovePolicyEntry(action: .place(pieceId: "tri-3", variantId: 0, origin: BoardPoint(x: 2, y: 2)), probability: 0.7),
        MovePolicyEntry(action: .pass, probability: 0.3),
      ],
      outcomeByPlayer: [
        PlayerValue(playerId: .blue, value: 0.5),
        PlayerValue(playerId: .yellow, value: -0.5),
      ]
    ),
  ]
}

private func writePositions(_ positions: [TrainingPosition], to path: URL) throws {
  FileManager.default.createFile(atPath: path.path, contents: nil)
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  let handle = try FileHandle(forWritingTo: path)
  defer { try? handle.close() }

  for position in positions {
    let data = try encoder.encode(position)
    handle.write(data)
    handle.write(Data([0x0A]))
  }
}
