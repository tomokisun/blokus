import Foundation

public struct TrainingDataOutputPaths: Sendable {
  public var directory: URL
  public var positions: URL
  public var games: URL
  public var metadata: URL

  public init(directory: URL, positions: URL, games: URL, metadata: URL) {
    self.directory = directory
    self.positions = positions
    self.games = games
    self.metadata = metadata
  }
}

public enum TrainingDataWriter {
  public static func write(
    _ result: SelfPlayBatchResult,
    to directory: URL,
    fileManager: FileManager = .default
  ) throws -> TrainingDataOutputPaths {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let positionsURL = directory.appendingPathComponent("positions.ndjson")
    let gamesURL = directory.appendingPathComponent("games.ndjson")
    let metadataURL = directory.appendingPathComponent("metadata.json")

    try writeLines(result.positions, to: positionsURL)
    try writeLines(result.games, to: gamesURL)
    try writeMetadata(result, to: metadataURL)

    return TrainingDataOutputPaths(
      directory: directory,
      positions: positionsURL,
      games: gamesURL,
      metadata: metadataURL
    )
  }

  private static func writeLines<T: Encodable>(
    _ entries: [T],
    to url: URL
  ) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let encoder = makeEncoder()
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    for entry in entries {
      let data = try encoder.encode(entry)
      handle.write(data)
      handle.write(Data([0x0A]))
    }
  }

  private static func writeMetadata(
    _ result: SelfPlayBatchResult,
    to url: URL
  ) throws {
    let encoder = makeEncoder(pretty: true)
    let metadata = TrainingMetadata(
      generatedAt: result.finishedAt,
      durationSec: result.finishedAt.timeIntervalSince(result.startedAt),
      configuration: result.configuration,
      gameCount: result.games.count,
      positionCount: result.positions.count
    )
    let data = try encoder.encode(metadata)
    try data.write(to: url, options: [.atomic])
  }

  private static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if pretty {
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    }
    return encoder
  }
}

private struct TrainingMetadata: Codable, Sendable {
  var generatedAt: Date
  var durationSec: TimeInterval
  var configuration: SelfPlayConfiguration
  var gameCount: Int
  var positionCount: Int
}
