import Foundation

enum Cell: Codable {
  case empty
  case occupied(pieceID: String, owner: PlayerColor)
}
