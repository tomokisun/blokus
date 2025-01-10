import Foundation

enum ComputerLevel: String, CaseIterable {
  case easy
  case normal
  case hard
  
  func makeComputer(for owner: Player) -> Computer {
    switch self {
    case .easy:
      return ComputerEasy(owner: owner)
      
    case .normal:
      return ComputerNormal(owner: owner)
      
    case .hard:
      return ComputerHard(owner: owner)
    }
  }
}
