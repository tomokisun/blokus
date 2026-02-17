#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain

extension PlayerID {
  public var color: Color {
    switch self {
    case .blue: return .blue
    case .yellow: return .yellow
    case .red: return .red
    case .green: return .green
    default: return .gray
    }
  }
}

public enum PlayerColor {
  public static func color(for playerIndex: Int) -> Color {
    PlayerID.allCases[playerIndex % PlayerID.allCases.count].color
  }

  public static func color(for playerId: PlayerID, in state: GameState) -> Color {
    playerId.color
  }
}
#endif
