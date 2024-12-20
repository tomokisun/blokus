import Foundation

enum Cell: Codable, Equatable {
  case empty
  case occupied(owner: Player)
}
