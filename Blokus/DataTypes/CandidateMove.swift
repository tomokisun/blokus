import Foundation

/// `CandidateMove` は、コンピュータが検討中の配置候補手を表す構造体です。
/// ピース本体、配置位置、回転状態、反転状態を持ちます。
struct CandidateMove {
  /// 配置を検討するピース。
  let piece: Piece
  /// ピースを配置する座標。
  let origin: Coordinate
  /// ピースの回転状態（0°, 90°, 180°, 270°）。
  let rotation: Rotation
  /// ピースが反転されているかどうか。
  let flipped: Bool
}
