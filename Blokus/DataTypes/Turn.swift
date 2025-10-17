import Foundation

struct Turn: Equatable, Codable {
  let index: Int
  let action: TurnAction
  let owner: Player
}

enum TurnAction: Equatable, Codable {
  case pass
  case place(piece: Piece, at: Coordinate)
}
