public struct Piece: Codable, Hashable, Sendable {
  public var id: String
  public var baseCells: [BoardPoint]

  public init(id: String, baseCells: [BoardPoint]) {
    self.id = id
    self.baseCells = baseCells
  }

  public var variants: [[BoardPoint]] {
    PieceVariantsCache.shared.variants(for: self)
  }
}

private final class PieceVariantsCache: @unchecked Sendable {
  static let shared = PieceVariantsCache()
  private var cache: [String: [[BoardPoint]]] = [:]

  func variants(for piece: Piece) -> [[BoardPoint]] {
    if let cached = cache[piece.id] { return cached }
    let canonicalBase = PieceVariantsCache.canonicalize(piece.baseCells)
    var generated: Set<String> = []
    var result: [[BoardPoint]] = []

    func add(_ cells: [BoardPoint]) {
      let normalized = PieceVariantsCache.canonicalize(cells)
      let key = normalized.map { "\($0.x),\($0.y)" }.joined(separator: "|")
      if !generated.contains(key) {
        generated.insert(key)
        result.append(normalized)
      }
    }

    var current = canonicalBase
    for _ in 0..<4 {
      add(current)
      add(current.map { BoardPoint(x: -$0.x, y: $0.y) })
      current = PieceVariantsCache.rotateClockwise(current)
    }
    cache[piece.id] = result
    return result
  }

  private static func rotateClockwise(_ points: [BoardPoint]) -> [BoardPoint] {
    let rotated = points.map { BoardPoint(x: $0.y, y: -$0.x) }
    return rotated
  }

  private static func canonicalize(_ points: [BoardPoint]) -> [BoardPoint] {
    guard let firstX = points.map(\.x).min(),
          let firstY = points.map(\.y).min() else {
      return []
    }
    return points
      .map { BoardPoint(x: $0.x - firstX, y: $0.y - firstY) }
      .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
  }
}

public enum PieceLibrary {
  public static let currentVersion = 5
  public static let pieces: [Piece] = [
    Piece(id: "mono-1", baseCells: [BoardPoint(x: 0, y: 0)]),
    Piece(id: "domino-2", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tri-3", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0)]),
    Piece(id: "tri-L-3", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tetri-I-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0)]),
    Piece(id: "tetri-L-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 0, y: 2), BoardPoint(x: 1, y: 0)]),
    Piece(id: "tetri-O-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1)]),
    Piece(id: "tetri-T-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 1, y: 1)]),
    Piece(id: "tetri-Z-4", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1)]),
    Piece(id: "penta-I-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 4, y: 0)]),
    Piece(id: "penta-P-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 0, y: 2)]),
    Piece(id: "penta-F-5", baseCells: [BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 0)]),
    Piece(id: "penta-L-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 0, y: 1)]),
    Piece(id: "penta-T-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 3, y: 0), BoardPoint(x: 1, y: 1)]),
    Piece(id: "penta-U-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 2, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1)]),
    Piece(id: "penta-V-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 0, y: 2), BoardPoint(x: 1, y: 0), BoardPoint(x: 2, y: 0)]),
    Piece(id: "penta-W-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 2, y: 2)]),
    Piece(id: "penta-X-5", baseCells: [BoardPoint(x: 1, y: 0), BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 1, y: 2)]),
    Piece(id: "penta-Y-5", baseCells: [BoardPoint(x: 0, y: 1), BoardPoint(x: 1, y: 1), BoardPoint(x: 2, y: 1), BoardPoint(x: 3, y: 1), BoardPoint(x: 1, y: 0)]),
    Piece(id: "penta-Z-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 2)]),
    Piece(id: "penta-N-5", baseCells: [BoardPoint(x: 0, y: 0), BoardPoint(x: 1, y: 0), BoardPoint(x: 1, y: 1), BoardPoint(x: 1, y: 2), BoardPoint(x: 2, y: 2)])
  ]
}
