public struct BoardPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public var isInsideBoard: Bool {
    x >= 0 && x < BoardConstants.boardSize && y >= 0 && y < BoardConstants.boardSize
  }

  public func translated(_ dx: Int, _ dy: Int) -> BoardPoint {
    BoardPoint(x: x + dx, y: y + dy)
  }
}
