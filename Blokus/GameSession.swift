import Foundation
import SwiftUI

@MainActor @Observable
final class GameSession {
  // MARK: - Configuration

  let computerMode: Bool
  let computerLevel: ComputerLevel

  // MARK: - State

  var board = Board()
  var pieces = Piece.allPieces
  var computerPlayers: [Computer]
  var player = Player.red
  let trunRecorder = TrunRecorder()
  var thinkingState = ComputerThinkingState.idle

  // MARK: - Initialization

  init(computerMode: Bool, computerLevel: ComputerLevel) {
    self.computerMode = computerMode
    self.computerLevel = computerLevel
    self.computerPlayers = [
      computerLevel.makeComputer(for: .blue),
      computerLevel.makeComputer(for: .green),
      computerLevel.makeComputer(for: .yellow)
    ]
  }

  // MARK: - Derived Values

  var playerPieces: [Piece] {
    pieces.filter { $0.owner == player }
  }

  // MARK: - Piece Operations

  func rotatePieces() {
    pieces = pieces.map { piece in
      var piece = piece
      piece.orientation.rotate90()
      return piece
    }
  }

  func flipPieces() {
    pieces = pieces.map { piece in
      var piece = piece
      piece.orientation.flip()
      return piece
    }
  }

  func updateHighlights(for piece: Piece?) {
    if let piece {
      board.highlightPossiblePlacements(for: piece)
    } else {
      board.clearHighlights()
    }
  }

  func placeHumanPiece(_ piece: Piece, at origin: Coordinate) throws(PlacementError) {
    try board.placePiece(piece: piece, at: origin)
    if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
      pieces.remove(at: index)
    }
  }

  func finalizeHumanTurn(with piece: Piece, at origin: Coordinate) async {
    await trunRecorder.recordPlaceAction(piece: piece, at: origin)
    await moveComputerPlayers()
  }

  func recordPass(for owner: Player) async {
    await trunRecorder.recordPassAction(owner: owner)
    await moveComputerPlayers()
  }

  // MARK: - Computer Actions

  private func moveComputerPlayers() async {
    guard computerMode else { return }

    for player in computerPlayers {
      do {
        let owner = await player.owner
        thinkingState = .thinking(owner)
        try await moveComputerPlayer(player)
        thinkingState = .idle
      } catch {
        print(error)
        thinkingState = .idle
      }
    }
  }

  private func moveComputerPlayer(_ computer: Computer) async throws(PlacementError) {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      await trunRecorder.recordPlaceAction(piece: candidate.piece, at: candidate.origin)

      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    } else {
      await trunRecorder.recordPassAction(owner: computer.owner)
    }
  }
}
