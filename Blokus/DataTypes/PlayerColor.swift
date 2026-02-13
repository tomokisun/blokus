import SwiftUI

// Player identity colors.
enum Player: String, Codable, Equatable, CaseIterable {
  case red = "Red"
  case blue = "Blue"
  case green = "Green"
  case yellow = "Yellow"
}

// Convert Player to SwiftUI Color.
extension Player {
  var localizedName: String {
    switch self {
    case .red:
      return String(localized: "Red")
    case .blue:
      return String(localized: "Blue")
    case .green:
      return String(localized: "Green")
    case .yellow:
      return String(localized: "Yellow")
    }
  }

  var color: Color {
    switch self {
    case .red: return .red
    case .blue: return .blue
    case .green: return .green
    case .yellow: return .yellow
    }
  }
}
