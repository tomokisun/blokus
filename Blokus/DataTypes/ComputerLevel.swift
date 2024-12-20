import Foundation

enum ComputerLevel: String, CaseIterable {
  case easy
  case normal
  case hard
  case master
  
  func makeComputer(for owner: Player) -> Computer {
    switch self {
    case .easy:
      return ComputerEasy(owner: owner)
      
    case .normal:
      return ComputerNormal(owner: owner)
      
    case .hard:
      return ComputerHard(owner: owner)
      
    case .master:
      return ComputerMaster(owner: owner)
    }
  }
}
