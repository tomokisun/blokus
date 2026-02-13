import Foundation

// Represents a piece on the board.
struct Piece: Codable, Identifiable, Equatable {
  let id: String
  let owner: Player
  // Base shape coordinates at 0° rotation and not flipped.
  let baseShape: [Coordinate]
  // Current orientation.
  var orientation: Orientation
}

extension Piece {
  func transformedShape() -> [Coordinate] {
    var transformed = baseShape
    
    // Apply rotation.
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
    
    // Apply horizontal flip.
    if orientation.flipped {
      transformed = transformed.map { Coordinate(x: -$0.x, y: $0.y) }
    }
    
    // Center-normalize: shift so the bounding box center is at (0,0).
    let xs = transformed.map(\.x)
    let ys = transformed.map(\.y)
    let centerX = (xs.min()! + xs.max()!) / 2
    let centerY = (ys.min()! + ys.max()!) / 2
    transformed = transformed.map { Coordinate(x: $0.x - centerX, y: $0.y - centerY) }

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
