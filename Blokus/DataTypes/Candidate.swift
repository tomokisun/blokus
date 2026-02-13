import Foundation

/// Represents the final chosen piece and its placement coordinate.
struct Candidate: Codable {
  /// Piece that will be placed.
  let piece: Piece
  /// Origin coordinate where the piece is placed.
  let origin: Coordinate
}
