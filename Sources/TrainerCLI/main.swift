import AICore
import Domain
import Foundation

@main
struct TrainerCLI {
  static func main() async {
    do {
      let command = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
      switch command {
      case let .selfPlay(options):
        try await runSelfPlay(options)
      case let .train(options):
        try runTrain(options)
      case let .eval(options):
        try await runEval(options)
      case let .export(options):
        try runExport(options)
      case .help:
        printUsage()
      }
    } catch {
      FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
      printUsage()
      Foundation.exit(1)
    }
  }

  private enum Command {
    case selfPlay(SelfPlayOptions)
    case train(TrainOptions)
    case eval(EvalOptions)
    case export(ExportOptions)
    case help
  }

  private struct SelfPlayOptions {
    var games: Int = 64
    var players: Int = 4
    var simulations: Int = 320
    var maxCandidates: Int = 48
    var maxTurns: Int = 320
    var parallelism: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    var temperature: Double = 0
    var seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    var outputDirectory: String = defaultSelfPlayOutputDirectory()
  }

  private struct TrainOptions {
    var dataPath: String = ""
    var outputPath: String = defaultModelOutputPath()
    var limit: Int?
    var label: String = defaultModelLabel()
    var policyBlend: Double = 0.65
    var valueBlend: Double = 0.7
    var selectedBoost: Double = 1.0
    var maxActionBiases: Int = 40000
    var ridgeLambda: Double = 1e-3
  }

  private struct EvalOptions {
    var modelAPath: String = ""
    var modelBPath: String = ""
    var games: Int = 64
    var players: Int = 4
    var simulations: Int = 160
    var maxCandidates: Int = 48
    var maxTurns: Int = 320
    var parallelism: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    var seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    var outputPath: String?
  }

  private struct ExportOptions {
    var modelPath: String = ""
    var outputDirectory: String = defaultExportDirectory()
  }

  private enum CLIError: LocalizedError {
    case missingSubcommand
    case unknownSubcommand(String)
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(String, String)
    case missingRequired(String)

    var errorDescription: String? {
      switch self {
      case .missingSubcommand:
        return "subcommandが必要です"
      case let .unknownSubcommand(name):
        return "不明なsubcommandです: \(name)"
      case let .unknownOption(option):
        return "不明なオプションです: \(option)"
      case let .missingValue(option):
        return "オプション値が不足しています: \(option)"
      case let .invalidValue(option, value):
        return "オプション値が不正です: \(option)=\(value)"
      case let .missingRequired(option):
        return "必須オプションが不足しています: \(option)"
      }
    }
  }

  private static func parse(arguments: [String]) throws -> Command {
    guard let subcommand = arguments.first else {
      throw CLIError.missingSubcommand
    }

    switch subcommand {
    case "help", "--help", "-h":
      return .help

    case "selfplay":
      var options = SelfPlayOptions()
      try parseSelfPlayOptions(arguments: arguments, options: &options)
      return .selfPlay(options)

    case "train":
      var options = TrainOptions()
      try parseTrainOptions(arguments: arguments, options: &options)
      guard !options.dataPath.isEmpty else {
        throw CLIError.missingRequired("--data")
      }
      return .train(options)

    case "eval":
      var options = EvalOptions()
      try parseEvalOptions(arguments: arguments, options: &options)
      guard !options.modelAPath.isEmpty else {
        throw CLIError.missingRequired("--model-a")
      }
      guard !options.modelBPath.isEmpty else {
        throw CLIError.missingRequired("--model-b")
      }
      return .eval(options)

    case "export":
      var options = ExportOptions()
      try parseExportOptions(arguments: arguments, options: &options)
      guard !options.modelPath.isEmpty else {
        throw CLIError.missingRequired("--model")
      }
      return .export(options)

    default:
      throw CLIError.unknownSubcommand(subcommand)
    }
  }

  private static func parseSelfPlayOptions(
    arguments: [String],
    options: inout SelfPlayOptions
  ) throws {
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      let (option, inlineValue) = splitOption(argument)

      switch option {
      case "--games":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.games = parsed

      case "--players":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), (2...4).contains(parsed) else {
          throw CLIError.invalidValue(option, value)
        }
        options.players = parsed

      case "--simulations":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.simulations = parsed

      case "--max-candidates":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.maxCandidates = parsed

      case "--max-turns":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.maxTurns = parsed

      case "--parallel", "--parallelism":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.parallelism = parsed

      case "--temperature":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Double(value), parsed >= 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.temperature = parsed

      case "--seed":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = UInt64(value) else {
          throw CLIError.invalidValue(option, value)
        }
        options.seed = parsed

      case "--output":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.outputDirectory = value

      default:
        throw CLIError.unknownOption(argument)
      }

      index += 1
    }
  }

  private static func parseTrainOptions(
    arguments: [String],
    options: inout TrainOptions
  ) throws {
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      let (option, inlineValue) = splitOption(argument)

      switch option {
      case "--data":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.dataPath = value

      case "--output":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.outputPath = value

      case "--limit":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.limit = parsed

      case "--label":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.label = value

      case "--policy-blend":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Double(value), (0...1).contains(parsed) else {
          throw CLIError.invalidValue(option, value)
        }
        options.policyBlend = parsed

      case "--value-blend":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Double(value), (0...1).contains(parsed) else {
          throw CLIError.invalidValue(option, value)
        }
        options.valueBlend = parsed

      case "--selected-boost":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Double(value), parsed >= 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.selectedBoost = parsed

      case "--max-action-biases":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.maxActionBiases = parsed

      case "--ridge":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Double(value), parsed >= 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.ridgeLambda = parsed

      default:
        throw CLIError.unknownOption(argument)
      }

      index += 1
    }
  }

  private static func parseEvalOptions(
    arguments: [String],
    options: inout EvalOptions
  ) throws {
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      let (option, inlineValue) = splitOption(argument)

      switch option {
      case "--model-a":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.modelAPath = value

      case "--model-b":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.modelBPath = value

      case "--games":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.games = parsed

      case "--players":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), (2...4).contains(parsed) else {
          throw CLIError.invalidValue(option, value)
        }
        options.players = parsed

      case "--simulations":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.simulations = parsed

      case "--max-candidates":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.maxCandidates = parsed

      case "--max-turns":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.maxTurns = parsed

      case "--parallel", "--parallelism":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = Int(value), parsed > 0 else {
          throw CLIError.invalidValue(option, value)
        }
        options.parallelism = parsed

      case "--seed":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        guard let parsed = UInt64(value) else {
          throw CLIError.invalidValue(option, value)
        }
        options.seed = parsed

      case "--output":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.outputPath = value

      default:
        throw CLIError.unknownOption(argument)
      }

      index += 1
    }
  }

  private static func parseExportOptions(
    arguments: [String],
    options: inout ExportOptions
  ) throws {
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      let (option, inlineValue) = splitOption(argument)

      switch option {
      case "--model":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.modelPath = value

      case "--output":
        let value = try value(for: option, inlineValue: inlineValue, arguments: arguments, index: &index)
        options.outputDirectory = value

      default:
        throw CLIError.unknownOption(argument)
      }

      index += 1
    }
  }

  private static func runSelfPlay(_ options: SelfPlayOptions) async throws {
    let config = SelfPlayConfiguration(
      games: options.games,
      players: options.players,
      maxTurns: options.maxTurns,
      parallelism: options.parallelism,
      baseSeed: options.seed,
      mcts: MCTSConfiguration(
        simulations: options.simulations,
        explorationConstant: 1.25,
        maxCandidateMoves: options.maxCandidates,
        temperature: options.temperature
      )
    )

    let runner = SelfPlayRunner(
      config: config,
      predictor: HeuristicPolicyValuePredictor()
    )

    print("selfplay started")
    print(
      "config: games=\(config.games), players=\(config.players), simulations=\(config.mcts.simulations), "
        + "maxCandidates=\(config.mcts.maxCandidateMoves), parallelism=\(config.parallelism)"
    )

    let batchResult = await runner.runBatch { progress in
      let completionRate = progress.totalGames > 0
        ? (Double(progress.completedGames) / Double(progress.totalGames)) * 100
        : 100
      let eta = progress.etaSec.map { formatDuration($0) } ?? "--:--"
      print(
        "[progress] \(progress.completedGames)/\(progress.totalGames) "
          + "(\(String(format: "%.1f", completionRate))%) "
          + "positions=\(progress.generatedPositions) "
          + "speed=\(String(format: "%.2f", progress.gamesPerSec)) game/s "
          + "elapsed=\(formatDuration(progress.elapsedSec)) "
          + "eta=\(eta)"
      )
    }

    let outputURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
    let paths = try TrainingDataWriter.write(batchResult, to: outputURL)

    let duration = batchResult.finishedAt.timeIntervalSince(batchResult.startedAt)
    let averageTurns = averageTurnsForGames(batchResult.games)
    let winnerStats = winnerStatsForGames(batchResult.games)

    print("selfplay completed")
    print("games: \(batchResult.games.count)")
    print("positions: \(batchResult.positions.count)")
    print(String(format: "duration: %.2fs", duration))
    print(String(format: "avg_turns: %.2f", averageTurns))
    if !winnerStats.isEmpty {
      print("winner_rate:")
      for (playerId, rate) in winnerStats {
        print(String(format: "  %@: %.2f%%", playerId.rawValue, rate * 100))
      }
    }
    print("output:")
    print("  positions: \(paths.positions.path)")
    print("  games: \(paths.games.path)")
    print("  metadata: \(paths.metadata.path)")
  }

  private static func runTrain(_ options: TrainOptions) throws {
    let dataURL = URL(fileURLWithPath: options.dataPath)
    let outputURL = URL(fileURLWithPath: options.outputPath)

    print("train started")
    print(
      "config: data=\(dataURL.path), output=\(outputURL.path), policyBlend=\(options.policyBlend), "
        + "valueBlend=\(options.valueBlend), maxActionBiases=\(options.maxActionBiases)"
    )

    let loadStart = Date()
    let positions = try TrainingDatasetReader.loadPositions(from: dataURL, limit: options.limit) { loaded in
      print("[progress] loaded_positions=\(loaded)")
    }
    let loadDuration = Date().timeIntervalSince(loadStart)

    let configuration = TrainerConfiguration(
      label: options.label,
      policyBlend: options.policyBlend,
      valueBlend: options.valueBlend,
      selectedActionBoost: options.selectedBoost,
      maxActionBiasCount: options.maxActionBiases,
      ridgeLambda: options.ridgeLambda
    )

    let trainStart = Date()
    let result = PolicyValueModelTrainer.train(positions: positions, configuration: configuration)
    let trainDuration = Date().timeIntervalSince(trainStart)

    try TrainedModelIO.save(result.model, to: outputURL)

    let metrics = result.model.metrics
    print("train completed")
    print("loaded_positions: \(positions.count) (\(String(format: "%.2fs", loadDuration)))")
    print("train_time: \(String(format: "%.2fs", trainDuration))")
    print("value_mse: \(String(format: "%.6f", metrics.valueMSE))")
    print("unique_actions: \(metrics.uniqueActionCount)")
    print("stored_action_biases: \(metrics.storedActionBiasCount)")
    print("output_model: \(outputURL.path)")
  }

  private static func runEval(_ options: EvalOptions) async throws {
    let modelAURL = URL(fileURLWithPath: options.modelAPath)
    let modelBURL = URL(fileURLWithPath: options.modelBPath)

    let modelA = try TrainedModelIO.load(from: modelAURL)
    let modelB = try TrainedModelIO.load(from: modelBURL)

    let config = ModelEvaluationConfiguration(
      games: options.games,
      players: options.players,
      maxTurns: options.maxTurns,
      parallelism: options.parallelism,
      baseSeed: options.seed,
      mcts: MCTSConfiguration(
        simulations: options.simulations,
        explorationConstant: 1.25,
        maxCandidateMoves: options.maxCandidates,
        temperature: 0
      )
    )

    print("eval started")
    print(
      "config: games=\(config.games), players=\(config.players), simulations=\(config.mcts.simulations), "
        + "parallelism=\(config.parallelism)"
    )
    print("model_a: \(modelAURL.path)")
    print("model_b: \(modelBURL.path)")

    let evaluator = ModelEvaluator(configuration: config)
    let result = await evaluator.evaluate(modelA: modelA, modelB: modelB) { progress in
      let completionRate = (Double(progress.completedGames) / Double(progress.totalGames)) * 100
      let eta = progress.etaSec.map { formatDuration($0) } ?? "--:--"
      print(
        "[progress] \(progress.completedGames)/\(progress.totalGames) "
          + "(\(String(format: "%.1f", completionRate))%) "
          + "speed=\(String(format: "%.2f", progress.gamesPerSec)) game/s "
          + "elapsed=\(formatDuration(progress.elapsedSec)) eta=\(eta)"
      )
    }

    print("eval completed")
    print(String(format: "win_rate_a: %.4f", result.winRateA))
    print(String(format: "win_rate_b: %.4f", result.winRateB))
    print(String(format: "avg_score_a: %.3f", result.avgScoreA))
    print(String(format: "avg_score_b: %.3f", result.avgScoreB))
    print(String(format: "avg_rank_a: %.3f", result.avgRankA))
    print(String(format: "avg_rank_b: %.3f", result.avgRankB))
    print(String(format: "estimated_elo_a: %.2f", result.estimatedEloA))
    print(String(format: "average_turns: %.2f", result.averageTurns))

    if let outputPath = options.outputPath {
      let outputURL = URL(fileURLWithPath: outputPath)
      try writeJSON(result, to: outputURL)
      print("output_report: \(outputURL.path)")
    }
  }

  private static func runExport(_ options: ExportOptions) throws {
    let modelURL = URL(fileURLWithPath: options.modelPath)
    let outputDirectoryURL = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)

    let sourceData = try Data(contentsOf: modelURL)
    let model = try TrainedModelIO.load(from: modelURL)

    print("export started")
    print("source_model: \(modelURL.path)")

    let paths = try ModelExporter.export(
      sourceModel: model,
      sourceModelData: sourceData,
      sourceModelPath: modelURL.path,
      to: outputDirectoryURL
    )

    print("export completed")
    print("output:")
    print("  inference_model: \(paths.inferenceModelPath.path)")
    print("  manifest: \(paths.manifestPath.path)")
  }

  private static func averageTurnsForGames(_ games: [SelfPlayGameSummary]) -> Double {
    guard !games.isEmpty else { return 0 }
    let total = games.reduce(0) { $0 + $1.turns }
    return Double(total) / Double(games.count)
  }

  private static func winnerStatsForGames(_ games: [SelfPlayGameSummary]) -> [(PlayerID, Double)] {
    guard !games.isEmpty else { return [] }

    var winnerCounts: [PlayerID: Double] = [:]
    for game in games {
      guard !game.winnerIds.isEmpty else { continue }
      let contribution = 1.0 / Double(game.winnerIds.count)
      for winner in game.winnerIds {
        winnerCounts[winner, default: 0] += contribution
      }
    }

    return winnerCounts
      .map { ($0.key, $0.value / Double(games.count)) }
      .sorted { lhs, rhs in lhs.0.rawValue < rhs.0.rawValue }
  }

  private static func splitOption(_ argument: String) -> (String, String?) {
    guard let separator = argument.firstIndex(of: "=") else {
      return (argument, nil)
    }
    return (
      String(argument[..<separator]),
      String(argument[argument.index(after: separator)...])
    )
  }

  private static func value(
    for option: String,
    inlineValue: String?,
    arguments: [String],
    index: inout Int
  ) throws -> String {
    if let inlineValue {
      return inlineValue
    }
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
      throw CLIError.missingValue(option)
    }
    index = valueIndex
    return arguments[valueIndex]
  }

  private static func defaultSelfPlayOutputDirectory() -> String {
    "TrainingRuns/\(timestamp())"
  }

  private static func defaultModelOutputPath() -> String {
    "Models/model-\(timestamp()).json"
  }

  private static func defaultModelLabel() -> String {
    "model-\(timestamp())"
  }

  private static func defaultExportDirectory() -> String {
    "Exports/export-\(timestamp())"
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private static func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hour = total / 3600
    let minute = (total % 3600) / 60
    let second = total % 60
    if hour > 0 {
      return String(format: "%d:%02d:%02d", hour, minute, second)
    }
    return String(format: "%02d:%02d", minute, second)
  }

  private static func writeJSON<T: Encodable>(_ value: T, to path: URL) throws {
    let parent = path.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: path, options: [.atomic])
  }

  private static func printUsage() {
    let usage = """
    Usage:
      swift run TrainerCLI selfplay [options]
      swift run TrainerCLI train --data <positions.ndjson|run-dir> [options]
      swift run TrainerCLI eval --model-a <path> --model-b <path> [options]
      swift run TrainerCLI export --model <path> [options]

    selfplay options:
      --games <int>            自己対戦局数 (default: 64)
      --players <2...4>        プレイヤー数 (default: 4)
      --simulations <int>      1手あたりMCTS反復数 (default: 320)
      --max-candidates <int>   展開候補手数の上限 (default: 48)
      --max-turns <int>        1局の最大手数 (default: 320)
      --parallel <int>         並列ワーカー数 (default: CPU-1)
      --temperature <double>   ルート温度 (default: 0)
      --seed <uint64>          乱数シード
      --output <path>          出力ディレクトリ

    train options:
      --data <path>            positions.ndjson または run ディレクトリ
      --output <path>          学習済みモデル出力先 (default: Models/model-*.json)
      --limit <int>            読み込む局面数の上限
      --label <string>         モデル名ラベル
      --policy-blend <0...1>   推論時の方策ブレンド比 (default: 0.65)
      --value-blend <0...1>    推論時の価値ブレンド比 (default: 0.7)
      --selected-boost <double> 選択手バイアスの強化量 (default: 1.0)
      --max-action-biases <int> 保存する手バイアス数 (default: 40000)
      --ridge <double>         価値線形回帰のL2正則化 (default: 0.001)

    eval options:
      --model-a <path>         比較対象Aモデル
      --model-b <path>         比較対象Bモデル
      --games <int>            評価局数 (default: 64)
      --players <2...4>        プレイヤー数 (default: 4)
      --simulations <int>      1手あたりMCTS反復数 (default: 160)
      --max-candidates <int>   展開候補手数 (default: 48)
      --max-turns <int>        1局最大手数 (default: 320)
      --parallel <int>         並列ワーカー数 (default: CPU-1)
      --seed <uint64>          乱数シード
      --output <path>          評価レポートJSON出力先

    export options:
      --model <path>           学習済みモデルJSON
      --output <path>          書き出し先ディレクトリ (default: Exports/export-*)
    """
    print(usage)
  }
}
