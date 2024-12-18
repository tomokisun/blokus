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
  var pieceSelection: Piece? {
    didSet {
      onChangePieces()
    }
  }
  
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

  func onChangePieces() {
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
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
          pieces.remove(at: index)
        }
      } completion: {
        Task(priority: .userInitiated) {
          do {
            try await self.moveComputerPlayer(self.computerPlayers[0])
            try await self.moveComputerPlayer(self.computerPlayers[1])
            try await self.moveComputerPlayer(self.computerPlayers[2])
          } catch {
            print(error)
          }
        }
      }
    } catch {
      print(error)
    }
  }
  
  // MARK: - Computer
  private func moveComputerPlayer(_ computer: ComputerPlayer) async throws {
    Task(priority: .userInitiated) {
      
    }
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
