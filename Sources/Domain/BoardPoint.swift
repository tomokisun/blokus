public struct BoardPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public var isInsideBoard: Bool {
    x >= 0 && x < 20 && y >= 0 && y < 20
  }

  public func translated(_ dx: Int, _ dy: Int) -> BoardPoint {
    BoardPoint(x: x + dx, y: y + dy)
  }
}
