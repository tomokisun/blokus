import Foundation

enum Cell: Codable {
  case empty
  case occupied(owner: PlayerColor)
}
