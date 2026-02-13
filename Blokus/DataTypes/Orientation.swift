import Foundation

// Represents piece orientation.
struct Orientation: Codable, Equatable {
  var rotation: Rotation
  var flipped: Bool
  
  mutating func rotate90() {
    rotation = rotation.rotate90()
  }
  
  mutating func flip() {
    flipped.toggle()
  }
}
