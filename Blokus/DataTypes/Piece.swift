import Foundation

// ピースを表す構造体
struct Piece: Codable, Identifiable, Equatable {
  let id: String
  let owner: Player
  // ピースの基本形。0度回転・非反転時の座標群
  let baseShape: [Coordinate]
  // 現在の向き
  var orientation: Orientation
}

extension Piece {
  func transformedShape() -> [Coordinate] {
    baseShape.map { $0.applying(orientation: orientation) }
  }
}

extension Piece {
  static var allPieces = coordinates.enumerated().map { index, shapes in
    Player.allCases.map { owner in
      Piece(
        id: "\(owner.rawValue):\(index)",
        owner: owner,
        baseShape: shapes,
        orientation: Orientation(rotation: .none, flipped: false)
      )
    }
  }.flatMap { $0 }
}
