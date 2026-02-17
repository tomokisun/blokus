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
}

public typealias GameID = String

public struct Player: Codable, Hashable, Sendable {
  public var id: PlayerID
  public var index: Int
  public var name: String
}
