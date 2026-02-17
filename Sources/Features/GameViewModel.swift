#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain
import Engine

@Observable
public final class GameViewModel {

  // MARK: - Properties

  public private(set) var engine: GameEngine
  public var selectedPieceId: String?
  public var selectedVariantIndex: Int = 0
  public var showHighlight: Bool = true
  public var isGameStarted: Bool = false

  // MARK: - Init

  public init() {
    let state = GameState(
      gameId: UUID().uuidString,
      players: Array(PlayerID.allCases),
      authorityId: .blue
    )
    self.engine = GameEngine(
      state: state,
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
  }

  // MARK: - Computed Properties

  public var currentState: GameState {
    engine.state
  }

  public var isGameOver: Bool {
    currentState.phase == .finished
  }

  public var activePlayerIndex: Int {
    currentState.activeIndex
  }

  public var remainingPiecesForCurrentPlayer: [Piece] {
    let activeId = currentState.activePlayerId
    let remaining = currentState.remainingPieces[activeId] ?? []
    return PieceLibrary.pieces.filter { remaining.contains($0.id) }
  }

  public var scores: [(playerId: PlayerID, score: Int)] {
    currentState.turnOrder.map { playerId in
      let score = currentState.board.filter({ $0 == playerId }).count
      return (playerId: playerId, score: score)
    }
  }

  public var canPass: Bool {
    !currentState.hasAnyLegalMove(for: currentState.activePlayerId)
  }

  public var selectedPieceVariant: [BoardPoint]? {
    guard let pieceId = selectedPieceId,
          let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else {
      return nil
    }
    let variants = piece.variants
    guard selectedVariantIndex >= 0, selectedVariantIndex < variants.count else {
      return nil
    }
    return variants[selectedVariantIndex]
  }

  public var highlightCells: Set<BoardPoint> {
    guard showHighlight,
          let pieceId = selectedPieceId,
          let variant = selectedPieceVariant else {
      return []
    }
    let activeId = currentState.activePlayerId
    var result = Set<BoardPoint>()
    for y in 0..<BoardConstants.boardSize {
      for x in 0..<BoardConstants.boardSize {
        let origin = BoardPoint(x: x, y: y)
        if currentState.canPlace(
          pieceId: pieceId,
          variantId: selectedVariantIndex,
          origin: origin,
          playerId: activeId
        ) {
          for cell in variant {
            let absolute = BoardPoint(x: cell.x + origin.x, y: cell.y + origin.y)
            result.insert(absolute)
          }
        }
      }
    }
    return result
  }

  public var winnerPlayerIds: [PlayerID] {
    let playerScores = scores
    guard let maxScore = playerScores.map(\.score).max(), maxScore > 0 else {
      return []
    }
    return playerScores.filter { $0.score == maxScore }.map(\.playerId)
  }

  // MARK: - Methods

  public func startGame(showHighlight: Bool) {
    let state = GameState(
      gameId: UUID().uuidString,
      players: Array(PlayerID.allCases),
      authorityId: .blue
    )
    self.engine = GameEngine(
      state: state,
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    self.showHighlight = showHighlight
    self.selectedPieceId = nil
    self.selectedVariantIndex = 0
    self.isGameStarted = true
  }

  public func selectPiece(_ pieceId: String) {
    selectedPieceId = pieceId
    selectedVariantIndex = 0
  }

  public func rotatePiece() {
    guard let pieceId = selectedPieceId,
          let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else {
      return
    }
    let variants = piece.variants
    guard !variants.isEmpty, selectedVariantIndex < variants.count else { return }
    let current = variants[selectedVariantIndex]
    let rotated = Self.canonicalize(current.map { BoardPoint(x: $0.y, y: -$0.x) })
    if let idx = variants.firstIndex(where: { Self.canonicalize($0) == rotated }) {
      selectedVariantIndex = idx
    } else {
      selectedVariantIndex = (selectedVariantIndex + 1) % variants.count
    }
  }

  public func flipPiece() {
    guard let pieceId = selectedPieceId,
          let piece = PieceLibrary.pieces.first(where: { $0.id == pieceId }) else {
      return
    }
    let variants = piece.variants
    guard !variants.isEmpty, selectedVariantIndex < variants.count else { return }
    let current = variants[selectedVariantIndex]
    let flipped = Self.canonicalize(current.map { BoardPoint(x: -$0.x, y: $0.y) })
    if let idx = variants.firstIndex(where: { Self.canonicalize($0) == flipped }) {
      selectedVariantIndex = idx
    } else {
      selectedVariantIndex = (selectedVariantIndex + 1) % variants.count
    }
  }

  private static func canonicalize(_ points: [BoardPoint]) -> [BoardPoint] {
    guard let minX = points.map(\.x).min(),
          let minY = points.map(\.y).min() else {
      return []
    }
    return points
      .map { BoardPoint(x: $0.x - minX, y: $0.y - minY) }
      .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
  }

  public func tapBoard(at point: BoardPoint) {
    guard let pieceId = selectedPieceId,
          let variant = selectedPieceVariant else { return }
    let activeId = currentState.activePlayerId

    // Try tapped point directly as origin (backward compatible)
    if currentState.canPlace(
      pieceId: pieceId,
      variantId: selectedVariantIndex,
      origin: point,
      playerId: activeId
    ) {
      submitPlacement(pieceId: pieceId, origin: point)
      return
    }

    // Reverse-search: for each cell in variant, compute candidate origin
    var bestOrigin: BoardPoint?
    var bestDistance = Int.max
    for cell in variant {
      let candidateOrigin = BoardPoint(x: point.x - cell.x, y: point.y - cell.y)
      guard candidateOrigin.x >= 0, candidateOrigin.y >= 0 else { continue }
      if currentState.canPlace(
        pieceId: pieceId,
        variantId: selectedVariantIndex,
        origin: candidateOrigin,
        playerId: activeId
      ) {
        let distance = abs(candidateOrigin.x - point.x) + abs(candidateOrigin.y - point.y)
        if distance < bestDistance {
          bestDistance = distance
          bestOrigin = candidateOrigin
        }
      }
    }

    if let origin = bestOrigin {
      submitPlacement(pieceId: pieceId, origin: origin)
    }
  }

  private func submitPlacement(pieceId: String, origin: BoardPoint) {
    let command = makeCommand(
      action: .place(pieceId: pieceId, variantId: selectedVariantIndex, origin: origin)
    )
    let status = engine.submit(command)
    switch status {
    case .accepted:
      selectedPieceId = nil
      selectedVariantIndex = 0
    default:
      break
    }
  }

  public func pass() {
    let command = makeCommand(action: .pass)
    _ = engine.submit(command)
    selectedPieceId = nil
    selectedVariantIndex = 0
  }

  public func backToMenu() {
    isGameStarted = false
  }

  // MARK: - Private

  private func makeCommand(action: CommandAction) -> GameCommand {
    let now = Date()
    return GameCommand(
      clientId: "local",
      expectedSeq: currentState.expectedSeq,
      playerId: currentState.activePlayerId,
      action: action,
      gameId: currentState.gameId,
      schemaVersion: GameState.schemaVersion,
      rulesVersion: GameState.rulesVersion,
      pieceSetVersion: PieceLibrary.currentVersion,
      issuedAt: now,
      issuedNanos: Int64(now.timeIntervalSince1970 * 1_000_000_000),
      nonce: Int64.random(in: Int64.min...Int64.max),
      authSig: ""
    )
  }
}
#endif
