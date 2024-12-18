import SwiftUI

// プレイヤーの色
enum PlayerColor: String, Codable, Equatable, CaseIterable {
  case red = "Red"
  case blue = "Blue"
  case green = "Green"
  case yellow = "Yellow"
}

// PlayerColorをSwiftUIのColorへ変換するための拡張
extension PlayerColor {
  var color: Color {
    switch self {
    case .red: return .red
    case .blue: return .blue
    case .green: return .green
    case .yellow: return .yellow
    }
  }
}
