import Foundation

// 向きを表す構造体
struct Orientation: Codable, Equatable {
  var rotation: Rotation
  var flipped: Bool
  
  mutating func rotate90Clockwise() {
    rotation = rotation.rotate90()
  }
}
