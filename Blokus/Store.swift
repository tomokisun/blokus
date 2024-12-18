import Foundation
import SwiftUI

@MainActor @Observable final class Store: AnyObject {
  let isHighlight: Bool
  let computerMode: Bool
  let computerLevel: ComputerLevel
  
  var board = Board()
  var pieces = Piece.allPieces
  var computerPlayers: [ComputerPlayer]
  
  var pieceSelection: Piece?
  
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

  
  // MARK: - Player
  func movePlayerPiece(at origin: Coordinate) {
    guard let piece = pieceSelection else { return }
    do {
      try board.placePiece(piece: piece, at: origin)
      
      withAnimation {
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
          pieces.remove(at: index)
        }
      }
      
      try moveComputerPlayer(computerPlayers[0])
      try moveComputerPlayer(computerPlayers[1])
      try moveComputerPlayer(computerPlayers[2])

    } catch {
      print(error)
    }
  }
  
  // MARK: - Computer
  private func moveComputerPlayer(_ computer: ComputerPlayer) throws {
    if let candidate = computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      
      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    }
  }
}
