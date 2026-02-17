import Foundation

public struct Board: Codable, Hashable, Sendable {
  public var cells: [PlayerID?]

  public init() {
    self.cells = Array(repeating: nil, count: BoardConstants.boardCellCount)
  }

  public init(cells: [PlayerID?]) {
    self.cells = cells
  }

  // MARK: - BoardPoint access

  public subscript(point: BoardPoint) -> PlayerID? {
    get { cells[Self.index(point)] }
    set { cells[Self.index(point)] = newValue }
  }

  // MARK: - Int index access (for backward compatibility)

  public subscript(index: Int) -> PlayerID? {
    get { cells[index] }
    set { cells[index] = newValue }
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
    cells.contains(where: predicate)
  }

  public func filter(_ isIncluded: (PlayerID?) -> Bool) -> [PlayerID?] {
    cells.filter(isIncluded)
  }

  public var indices: Range<Int> {
    cells.indices
  }
}
