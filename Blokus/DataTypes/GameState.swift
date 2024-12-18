import Foundation

enum GameState: Equatable {
  case newGame
  case playing(computerMode: Bool, computerLevel: ComputerLevel, isHighlight: Bool)
}
