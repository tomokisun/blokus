import Foundation

enum ComputerThinkingState: Equatable {
  case idle
  case thinking(Player)
}
