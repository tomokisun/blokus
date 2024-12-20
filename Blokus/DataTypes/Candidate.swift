import Foundation

/// `Candidate` は、最終的に選択されたコマとその配置座標を表します。
struct Candidate: Codable {
  /// 配置するピース。
  let piece: Piece
  /// ピースを配置する座標。
  let origin: Coordinate
}
