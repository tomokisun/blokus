import Foundation

public struct PlayerID: RawRepresentable, Codable, Hashable, Sendable, CaseIterable,
                        ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public static let blue = PlayerID(rawValue: "Blue")
  public static let yellow = PlayerID(rawValue: "Yellow")
  public static let red = PlayerID(rawValue: "Red")
  public static let green = PlayerID(rawValue: "Green")

  public static var allCases: [PlayerID] { [.blue, .yellow, .red, .green] }
  public var displayName: String { rawValue }
  public var description: String { rawValue }

  /// Compact 1-based index for board storage. 0 = empty.
  public var compactIndex: UInt8 {
    switch self {
    case .blue: return 1
    case .yellow: return 2
    case .red: return 3
    case .green: return 4
    default: return 0
    }
  }

  /// Restore from compact index. Returns nil for 0 (empty).
  public static func from(compactIndex: UInt8) -> PlayerID? {
    switch compactIndex {
    case 1: return .blue
    case 2: return .yellow
    case 3: return .red
    case 4: return .green
    default: return nil
    }
  }
}

public typealias GameID = String

public struct Player: Codable, Hashable, Sendable {
  public var id: PlayerID
  public var index: Int
  public var name: String
  public var isAI: Bool

  public init(id: PlayerID, index: Int, name: String, isAI: Bool = false) {
    self.id = id
    self.index = index
    self.name = name
    self.isAI = isAI
  }
}
