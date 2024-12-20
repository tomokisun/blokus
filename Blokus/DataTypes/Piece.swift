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
    var transformed = baseShape
    
    // 回転適用
    switch orientation.rotation {
    case .none:
      break
    case .ninety:
      // (x,y) -> (y, -x)
      transformed = transformed.map { Coordinate(x: $0.y, y: -$0.x) }
    case .oneEighty:
      // (x,y) -> (-x, -y)
      transformed = transformed.map { Coordinate(x: -$0.x, y: -$0.y) }
    case .twoSeventy:
      // (x,y) -> (-y, x)
      transformed = transformed.map { Coordinate(x: -$0.y, y: $0.x) }
    }
    
    // 反転適用 (水平反転とする)
    if orientation.flipped {
      transformed = transformed.map { Coordinate(x: -$0.x, y: $0.y) }
    }
    
    return transformed
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
