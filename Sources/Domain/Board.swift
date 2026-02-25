import Foundation

public struct Board: Hashable, Sendable {
  /// Compact storage: 0=empty, 1=blue, 2=yellow, 3=red, 4=green
  public var rawCells: [UInt8]

  public init() {
    self.rawCells = Array(repeating: 0, count: BoardConstants.boardCellCount)
  }

  public init(rawCells: [UInt8]) {
    self.rawCells = rawCells
  }

  /// Compatibility: initialize from [PlayerID?]
  public init(cells: [PlayerID?]) {
    self.rawCells = cells.map { $0?.compactIndex ?? 0 }
  }

  /// Compatibility: read cells as [PlayerID?]
  public var cells: [PlayerID?] {
    rawCells.map { PlayerID.from(compactIndex: $0) }
  }

  // MARK: - BoardPoint access

  public subscript(point: BoardPoint) -> PlayerID? {
    get { PlayerID.from(compactIndex: rawCells[Self.index(point)]) }
    set { rawCells[Self.index(point)] = newValue?.compactIndex ?? 0 }
  }

  // MARK: - Int index access

  public subscript(index: Int) -> PlayerID? {
    get { PlayerID.from(compactIndex: rawCells[index]) }
    set { rawCells[index] = newValue?.compactIndex ?? 0 }
  }

  // MARK: - Index conversion

  public static func index(_ point: BoardPoint) -> Int {
    point.y * BoardConstants.boardSize + point.x
  }

  public static func boardPoint(for index: Int) -> BoardPoint {
    BoardPoint(x: index % BoardConstants.boardSize, y: index / BoardConstants.boardSize)
  }

  // MARK: - Queries

  public func contains(where predicate: (PlayerID?) -> Bool) -> Bool {
    rawCells.contains { predicate(PlayerID.from(compactIndex: $0)) }
  }

  public func filter(_ isIncluded: (PlayerID?) -> Bool) -> [PlayerID?] {
    rawCells.compactMap { PlayerID.from(compactIndex: $0) }.filter(isIncluded).map { Optional($0) }
  }

  public var indices: Range<Int> {
    rawCells.indices
  }
}

// MARK: - Codable (encode/decode as [PlayerID?] for compatibility)

extension Board: Codable {
  private enum CodingKeys: String, CodingKey {
    case cells
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let playerCells = try container.decode([PlayerID?].self, forKey: .cells)
    self.rawCells = playerCells.map { $0?.compactIndex ?? 0 }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cells, forKey: .cells)
  }
}
