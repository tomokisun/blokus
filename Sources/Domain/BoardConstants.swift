import Foundation

public enum BoardConstants {
  public static let boardSize = 20
  public static let boardCellCount = boardSize * boardSize
  public static let maxBoardIndex = boardSize - 1

  public static let playerStartCorners: [BoardPoint] = [
    BoardPoint(x: 0, y: 0),
    BoardPoint(x: maxBoardIndex, y: maxBoardIndex),
    BoardPoint(x: maxBoardIndex, y: 0),
    BoardPoint(x: 0, y: maxBoardIndex),
  ]
}
