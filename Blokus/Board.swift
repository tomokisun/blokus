import Foundation

/// `Board` is the complete board model for a Blokus game.
///
/// - `cells`: occupancy information for each board position.
/// - `highlightedCoordinates`: coordinates used for placement highlighting.
///
/// `x` is the column and `y` is the row in the 0-based coordinate system
/// (`0..Board.width-1`, `0..Board.height-1`).
struct Board: Equatable {

  static let width = 20
  static let height = 20

  /// Board data is stored as a 0-based `[x][y]` matrix.
  var cells: [[Cell]] = Array(
    repeating: Array(repeating: Cell(owner: nil), count: Board.width),
    count: Board.height
  )

  /// Cells used for highlight overlays in UI rendering.
  var highlightedCoordinates: Set<Coordinate> = []

  /// Cells used for placement preview overlays in UI rendering.
  var previewCoordinates: Set<Coordinate> = []

  @inline(__always)
  func isInside(_ coordinate: Coordinate) -> Bool {
    coordinate.x >= 0 && coordinate.x < Board.width &&
      coordinate.y >= 0 && coordinate.y < Board.height
  }

  /// Returns the `Cell` for the coordinate.
  /// Returns `nil` when the coordinate is outside the board.
  @inline(__always)
  func cell(at coordinate: Coordinate) -> Cell? {
    guard isInside(coordinate) else { return nil }
    return cells[coordinate.x][coordinate.y]
  }

  /// Returns the owner at the coordinate.
  /// Returns `nil` when the coordinate is outside the board.
  @inline(__always)
  func owner(at coordinate: Coordinate) -> Player? {
    return cell(at: coordinate)?.owner
  }

  /// Does nothing when `cell(at:)` returns `nil`.
  mutating func setOwner(_ owner: Player?, at coordinate: Coordinate) {
    guard isInside(coordinate) else { return }
    cells[coordinate.x][coordinate.y] = Cell(owner: owner)
  }

  /// Returns all cell coordinates for the specified player.
  func playerCells(owner: Player) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        if cells[x][y].owner == owner {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
  }
}
