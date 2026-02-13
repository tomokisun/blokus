import Foundation

/// Represents a candidate move considered by the AI.
/// Includes piece, placement coordinate, rotation, and flip flags.
struct CandidateMove {
  /// Piece to evaluate.
  let piece: Piece
  /// Coordinate where the piece is placed.
  let origin: Coordinate
  /// Piece rotation state (`0°`, `90°`, `180°`, `270°`).
  let rotation: Rotation
  /// Whether the piece is flipped.
  let flipped: Bool
}
