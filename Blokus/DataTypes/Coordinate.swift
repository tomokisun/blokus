import Foundation

// 座標を表す構造体
struct Coordinate: Codable, Hashable, Equatable {
  let x: Int
  let y: Int
}

extension Coordinate {
  /// 斜め方向の近傍セルを取得します。
  ///
  /// - Parameter coord: 基準となる座標
  /// - Returns: 4方向の斜め近傍セル座標の配列
  func diagonalNeighbors() -> [Coordinate] {
    return [
      Coordinate(x: x-1, y: y-1),
      Coordinate(x: x+1, y: y-1),
      Coordinate(x: x-1, y: y+1),
      Coordinate(x: x+1, y: y+1)
    ]
  }

  /// 上下左右方向の近傍セルを取得します。
  ///
  /// - Parameter coord: 基準となる座標
  /// - Returns: 上下左右4方向の近傍セル座標の配列
  func edgeNeighbors() -> [Coordinate] {
    return [
      Coordinate(x: x, y: y-1),
      Coordinate(x: x, y: y+1),
      Coordinate(x: x-1, y: y),
      Coordinate(x: x+1, y: y)
    ]
  }
}

let coordinates: [[Coordinate]] = [
  .a, .b, .c, .d, .e, .f, .g, .h, .i, .j,
  .k, .l,.m, .n, .o, .p, .q, .r, .s, .t, .u,
]

extension Array where Element == Coordinate {
  // MARK: - 1マス (a)

  /// ```
  /// ■
  /// ```
  static let a = [
    Coordinate(x: 0, y: 0)
  ]
  
  // MARK: - 2マス (b)

  /// ```
  /// ■
  /// ■
  /// ```
  static let b = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1)
  ]
  
  // MARK: - 3マス (c, d)

  /// ```
  /// ■
  /// ■
  /// ■
  /// ```
  static let c = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 0, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■ ■
  /// ```
  static let d = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1)
  ]
  
  // MARK: - 4マス (e, f, g, h, i)
  
  /// ```
  /// ■
  /// ■
  /// ■
  /// ■
  /// ```
  static let e = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 0, y: 3)
  ]
  
  /// ```
  ///   ■
  ///   ■
  /// ■ ■
  /// ```
  static let f = [
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 1, y: 2),
    Coordinate(x: 0, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■ ■
  /// ■
  /// ```
  static let g = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 0, y: 2)
  ]
  
  /// ```
  /// ■ ■
  /// ■ ■
  /// ```
  static let h = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1)
  ]
  
  /// ```
  /// ■ ■
  ///   ■ ■
  /// ```
  static let i = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 2, y: 1)
  ]
  
  // MARK: - 5マス (j～u)
  /// ```
  /// ■
  /// ■
  /// ■
  /// ■
  /// ■
  /// ```
  static let j = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 0, y: 3),
    Coordinate(x: 0, y: 4)
  ]
  
  /// ```
  /// ■
  /// ■
  /// ■
  /// ■ ■
  /// ```
  static let k = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 0, y: 3),
    Coordinate(x: 1, y: 3)
  ]
  
  /// ```
  ///   ■
  ///   ■
  /// ■ ■
  /// ■
  /// ```
  static let l = [
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 1, y: 2),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 0, y: 3)
  ]
  
  /// ```
  ///   ■
  /// ■ ■
  /// ■ ■
  /// ```
  static let m = [
    Coordinate(x: 1, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 1, y: 2)
  ]
  
  /// ```
  /// ■ ■
  ///   ■
  /// ■ ■
  /// ```
  static let n = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 1, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■ ■
  /// ■
  /// ■
  /// ```
  static let o = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 0, y: 3)
  ]
  
  /// ```
  ///   ■
  ///   ■
  /// ■ ■ ■
  /// ```
  static let p = [
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 1, y: 2),
    Coordinate(x: 2, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■
  /// ■ ■ ■
  /// ```
  static let q = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 0, y: 2),
    Coordinate(x: 1, y: 2),
    Coordinate(x: 2, y: 2)
  ]
  
  /// ```
  /// ■ ■
  ///   ■ ■
  ///     ■
  /// ```
  static let r = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 1, y: 0),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 2, y: 1),
    Coordinate(x: 2, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■ ■ ■
  ///     ■
  /// ```
  static let s = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 2, y: 1),
    Coordinate(x: 2, y: 2)
  ]
  
  /// ```
  /// ■
  /// ■ ■ ■
  ///   ■
  /// ```
  static let t = [
    Coordinate(x: 0, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 2, y: 1),
    Coordinate(x: 1, y: 2)
  ]
  
  /// ```
  ///   ■
  /// ■ ■ ■
  ///   ■
  /// ```
  static let u = [
    Coordinate(x: 1, y: 0),
    Coordinate(x: 0, y: 1),
    Coordinate(x: 1, y: 1),
    Coordinate(x: 2, y: 1),
    Coordinate(x: 1, y: 2)
  ]
}
