import SwiftUI

// プレイヤーの色
enum Player: String, Codable, Equatable, CaseIterable {
  case red = "Red"
  case blue = "Blue"
  case green = "Green"
  case yellow = "Yellow"
}

// PlayerをSwiftUIのColorへ変換するための拡張
extension Player {
  var color: Color {
    switch self {
    case .red: return .red
    case .blue: return .blue
    case .green: return .green
    case .yellow: return .yellow
    }
  }
}
