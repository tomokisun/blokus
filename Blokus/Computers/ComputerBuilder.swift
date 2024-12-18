import Foundation

enum ComputerBuilder {
  static func make(for player: PlayerColor, level: ComputerLevel) -> Computer {
    switch level {
    case .easy:
      return ComputerEasy(owner: player)
      
    case .normal:
      return ComputerNormal(owner: player)
    }
  }
}
