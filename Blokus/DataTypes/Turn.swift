import Foundation

struct Trun: Equatable, Codable {
  let index: Int
  let action: TrunAction
  let owner: Player
}

enum TrunAction: Equatable, Codable {
  case pass
  case place(piece: Piece, at: Coordinate)
}
