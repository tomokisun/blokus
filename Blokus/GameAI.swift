import ComposableArchitecture
import Dependencies
import Foundation

// MARK: - Domain Snapshot and Determinism

struct ReadOnlyGameStateSnapshot: Equatable, Sendable {
  let board: Board
  let pieces: [Piece]
  let player: Player
  let turnIndex: Int
  let revision: Int
  let consecutivePasses: Int
  let isGameOver: Bool
  let isHighlight: Bool
  let computerMode: Bool
  let computerLevel: ComputerLevel
  let schemaVersion: Int

  init(
    board: Board,
    pieces: [Piece],
    player: Player,
    turnIndex: Int,
    revision: Int,
    consecutivePasses: Int,
    isGameOver: Bool,
    isHighlight: Bool,
    computerMode: Bool,
    computerLevel: ComputerLevel,
    schemaVersion: Int = 1
  ) {
    self.board = board
    self.pieces = pieces
    self.player = player
    self.turnIndex = turnIndex
    self.revision = revision
    self.consecutivePasses = consecutivePasses
    self.isGameOver = isGameOver
    self.isHighlight = isHighlight
    self.computerMode = computerMode
    self.computerLevel = computerLevel
    self.schemaVersion = schemaVersion
  }

  var digest: String {
    let boardDigest = board.cells
      .flatMap { $0 }
      .map { cell in
        cell.owner?.rawValue ?? "-"
      }
      .joined(separator: "#")

    let pieceDigest = pieces
      .sorted { $0.id < $1.id }
      .map {
        "\($0.id)|\($0.orientation.rotation.rawValue)|\($0.orientation.flipped ? 1 : 0)"
      }
      .joined(separator: "#")

    return [
      "\(schemaVersion)",
      "\(turnIndex)",
      "\(revision)",
      isGameOver ? "1" : "0",
      "\(consecutivePasses)",
      player.rawValue,
      isHighlight ? "1" : "0",
      computerMode ? "1" : "0",
      computerLevel.rawValue,
      boardDigest,
      pieceDigest
    ].joined(separator: "#")
  }
}

enum MoveDecision: Equatable, Sendable {
  case place(piece: Piece, at: Coordinate)
  case pass
}

protocol AIEngineClient: Sendable {
  func nextMove(_ snapshot: ReadOnlyGameStateSnapshot) async throws -> MoveDecision
}

struct TestAIEngineClient: AIEngineClient {
  var result: MoveDecision = .pass

  func nextMove(_ snapshot: ReadOnlyGameStateSnapshot) async throws -> MoveDecision {
    result
  }
}

struct RandomAIEngineClient: AIEngineClient {
  func nextMove(_ snapshot: ReadOnlyGameStateSnapshot) async throws -> MoveDecision {
    guard snapshot.computerMode else {
      return .pass
    }

    let candidates = Self.generateCandidateMoves(
      board: snapshot.board,
      snapshotPieces: snapshot.pieces,
      player: snapshot.player
    )

    guard let candidate = candidates.randomElement() else {
      return .pass
    }

    return .place(piece: candidate.piece, at: candidate.origin)
  }

  private static func generateCandidateMoves(
    board: Board,
    snapshotPieces: [Piece],
    player: Player
  ) -> [Candidate] {
    let targetPieces = snapshotPieces.filter { $0.owner == player }
    guard !targetPieces.isEmpty else { return [] }

    let rotations: [Rotation] = [.none, .ninety, .oneEighty, .twoSeventy]
    let flipOptions: [Bool] = [false, true]
    var result: [Candidate] = []

    for piece in targetPieces {
      var seenShapes: Set<String> = []
      for rotation in rotations {
        for flipped in flipOptions {
          var oriented = piece
          oriented.orientation = Orientation(rotation: rotation, flipped: flipped)
          let normalizedShapeKey = normalizedShapeKey(for: oriented.transformedShape())
          if seenShapes.contains(normalizedShapeKey) {
            continue
          }
          seenShapes.insert(normalizedShapeKey)

          for x in 0..<Board.width {
            for y in 0..<Board.height {
              let origin = Coordinate(x: x, y: y)
              if BoardLogic.canPlacePiece(piece: oriented, at: origin, in: board) {
                result.append(Candidate(piece: oriented, origin: origin))
              }
            }
          }
        }
      }
    }

    return result
  }

  private static func normalizedShapeKey(for coordinates: [Coordinate]) -> String {
    normalize(coordinates)
      .sorted { lhs, rhs in
        if lhs.y == rhs.y {
          return lhs.x < rhs.x
        }
        return lhs.y < rhs.y
      }
      .map { "\($0.x):\($0.y)" }
      .joined(separator: "|")
  }

  private static func normalize(_ coordinates: [Coordinate]) -> [Coordinate] {
    let minX = coordinates.map(\.x).min() ?? 0
    let minY = coordinates.map(\.y).min() ?? 0
    return coordinates.map { Coordinate(x: $0.x - minX, y: $0.y - minY) }
  }
}

enum AIEngineClientKey: TestDependencyKey {
  static var liveValue: any AIEngineClient { RandomAIEngineClient() }
  static var testValue: any AIEngineClient { TestAIEngineClient() }
  static var previewValue: any AIEngineClient { RandomAIEngineClient() }
}

extension DependencyValues {
  var aiEngineClient: any AIEngineClient {
    get { self[AIEngineClientKey.self] }
    set { self[AIEngineClientKey.self] = newValue }
  }
}
