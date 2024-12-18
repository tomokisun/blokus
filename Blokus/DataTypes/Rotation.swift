import Foundation

// 回転を表すenum (90度刻み)
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
