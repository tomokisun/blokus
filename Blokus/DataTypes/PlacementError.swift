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
      return "ピースがボード外にはみ出しています"
    case .cellOccupied:
      return "その位置には既に駒が置かれています"
    case .firstMoveMustIncludeCorner:
      return "初回配置はプレイヤーのコーナーセルを含めなければなりません"
    case .mustTouchOwnPieceByCorner:
      return "自分の駒と少なくとも一つの角で接していません"
    case .cannotShareEdgeWithOwnPiece:
      return "自分の駒と辺で接してはいけません（角接触のみ可）"
    }
  }
}
