import Foundation

enum PlacementError: Error, LocalizedError {
  case outOfBounds
  case cellOccupied
  case firstMoveMustIncludeCorner
  case mustTouchOwnPieceByCorner
  case cannotShareEdgeWithOwnPiece
  
  var errorDescription: String? {
    switch self {
    case .outOfBounds:
      return String(localized: "Piece is out of board.")
    case .cellOccupied:
      return String(localized: "A piece is already placed there.")
    case .firstMoveMustIncludeCorner:
      return String(localized: "The first move must include your corner cell.")
    case .mustTouchOwnPieceByCorner:
      return String(localized: "Must touch your own piece at least at one corner.")
    case .cannotShareEdgeWithOwnPiece:
      return String(localized: "You cannot share an edge with your own pieces.")
    }
  }
}
