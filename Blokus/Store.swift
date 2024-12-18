import Foundation
import SwiftUI

@MainActor @Observable final class Store: AnyObject {
  let isHighlight: Bool
  let computerMode: Bool
  let computerLevel: ComputerLevel
  
  var board = Board()
  var pieces = Piece.allPieces
  var computerPlayers: [ComputerPlayer]
  
  var player = PlayerColor.red
  var pieceSelection: Piece?

  var playerPieces: [Piece] {
    pieces.filter { $0.owner == player }
  }
  
  init(
    isHighlight: Bool,
    computerMode: Bool,
    computerLevel: ComputerLevel
  ) {
    self.isHighlight = isHighlight
    self.computerMode = computerMode
    self.computerLevel = computerLevel

    self.computerPlayers = [
      ComputerPlayer(owner: .blue, level: computerLevel),
      ComputerPlayer(owner: .green, level: computerLevel),
      ComputerPlayer(owner: .yellow, level: computerLevel)
    ]
  }
  
  // MARK: - Piece
  
  func rotatePiece() {
    withAnimation(.default) {
      pieces = pieces.map {
        var piece = $0
        piece.orientation.rotate90()
        return piece
      }
    }
  }
  
  func flipPiece() {
    withAnimation(.default) {
      pieces = pieces.map {
        var piece = $0
        piece.orientation.flip()
        return piece
      }
    }
  }

  func updateBoardHighlights() {
    guard isHighlight else { return }
    if let piece = pieceSelection {
      board.highlightPossiblePlacements(for: piece)
    } else {
      board.clearHighlights()
    }
  }
  
  // MARK: - Player
  func movePlayerPiece(at origin: Coordinate) {
    guard let piece = pieceSelection else { return }
    do {
      try board.placePiece(piece: piece, at: origin)
      
      withAnimation {
        pieceSelection = nil
        updateBoardHighlights()
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
          pieces.remove(at: index)
        }
      } completion: {
        Task(priority: .userInitiated) {
          await self.moveComputerPlayers()
        }
      }
    } catch {
      print(error)
    }
  }
  
  private func moveComputerPlayers() async {
    for player in computerPlayers {
      do {
        try await moveComputerPlayer(player)
      } catch {
        print(error)
      }
    }
  }
  
  // MARK: - Computer
  private func moveComputerPlayer(_ computer: ComputerPlayer) async throws {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      
      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    }
  }
}
