import Foundation

// Rotation values in 90-degree increments.
enum Rotation: Double, Codable, Equatable {
  case none = 0
  case ninety = 90
  case oneEighty = 180
  case twoSeventy = 270
  
  func rotate90() -> Rotation {
    switch self {
    case .none:
      return .ninety
    case .ninety:
      return .oneEighty
    case .oneEighty:
      return .twoSeventy
    case .twoSeventy:
      return .none
    }
  }
}
