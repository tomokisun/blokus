import Foundation

enum ComputerLevel: String, CaseIterable {
  case easy

  var localizedName: String {
    switch self {
    case .easy:
      return String(localized: "Easy")
    }
  }

  func makeComputer(for owner: Player) -> Computer {
    switch self {
    case .easy:
      return ComputerEasy(owner: owner)
    }
  }
}
