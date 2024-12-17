import SwiftUI

// 座標を表す構造体
struct Coordinate: Codable, Hashable, Equatable {
  let x: Int
  let y: Int
}

// プレイヤーの色
enum PlayerColor: Int, Codable, Equatable, CaseIterable {
  case red = 1
  case blue = 100
  case green = 10000
  case yellow = 1000000
}

// 回転を表すenum (90度刻み)
enum Rotation: Double, Codable, Equatable {
  case none = 0
  case ninety = 90
  case oneEighty = 180
  case twoSeventy = 270
  
  func rotate90() -> Rotation {
    switch self {
    case .none:
      return .ninety
    case .ninety:
      return .oneEighty
    case .oneEighty:
      return .twoSeventy
    case .twoSeventy:
      return .none
    }
  }
}

// 向きを表す構造体
struct Orientation: Codable, Equatable {
  var rotation: Rotation
  var flipped: Bool
  
  mutating func rotate90Clockwise() {
    rotation = rotation.rotate90()
  }
}

// ピースを表す構造体
struct Piece: Codable, Identifiable, Equatable {
  let id: Int
  let owner: PlayerColor
  // ピースの基本形。0度回転・非反転時の座標群
  let baseShape: [Coordinate]
  // 現在の向き
  var orientation: Orientation
}

extension Piece {
  func transformedShape() -> [Coordinate] {
    var transformed = baseShape
    
    // 回転適用
    switch orientation.rotation {
    case .none:
      break
    case .ninety:
      // (x,y) -> (y, -x)
      transformed = transformed.map { Coordinate(x: $0.y, y: -$0.x) }
    case .oneEighty:
      // (x,y) -> (-x, -y)
      transformed = transformed.map { Coordinate(x: -$0.x, y: -$0.y) }
    case .twoSeventy:
      // (x,y) -> (-y, x)
      transformed = transformed.map { Coordinate(x: -$0.y, y: $0.x) }
    }
    
    // 反転適用 (水平反転とする)
    if orientation.flipped {
      transformed = transformed.map { Coordinate(x: -$0.x, y: $0.y) }
    }
    
    return transformed
  }
}

// PlayerColorをSwiftUIのColorへ変換するための拡張
extension PlayerColor {
  var color: Color {
    switch self {
    case .red: return .red
    case .blue: return .blue
    case .green: return .green
    case .yellow: return .yellow
    }
  }
}

/// ボード上の1マスを表す構造体
/// empty: 駒なし
/// occupied: 駒あり
/// highlighted: ハイライトなどの用途で使用可能(必須ではない)
enum Cell: Codable {
  case empty
  case occupied(pieceID: Int, owner: PlayerColor)
}

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

/// Blokusのゲームボード全体を表す構造体
/// デフォルトでは20x20のボードを用意する
struct Board: Codable {
  let width: Int
  let height: Int
  var cells: [[Cell]]
  
  var hasPlacedFirstPiece: [PlayerColor: Bool] = [
    .red: false,
    .blue: false,
    .green: false,
    .yellow: false
  ]
  
  // ハイライト用の座標集合を追加
  var highlightedCoordinates: Set<Coordinate> = []
  
  /// 指定した幅・高さで初期化する
  init(width: Int = 20, height: Int = 20) {
    self.width = width
    self.height = height
    self.cells = Array(
      repeating: Array(repeating: Cell.empty, count: width),
      count: height
    )
  }
  
  /// 指定した座標がボード上に存在するかをチェック
  func isValidCoordinate(_ c: Coordinate) -> Bool {
    return c.x >= 0 && c.x < width && c.y >= 0 && c.y < height
  }
  
  /// 各プレイヤーの開始コーナーを返す
  func startingCorner(for player: PlayerColor) -> Coordinate {
    switch player {
    case .red:
      return Coordinate(x: 0, y: 0)
    case .blue:
      return Coordinate(x: width - 1, y: 0)
    case .green:
      return Coordinate(x: width - 1, y: height - 1)
    case .yellow:
      return Coordinate(x: 0, y: height - 1)
    }
  }
  
  func getPlayerCells(owner: PlayerColor) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for y in 0..<height {
      for x in 0..<width {
        if case let .occupied(_, cellOwner) = cells[y][x], cellOwner == owner {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
  }
  
  /// ピースを配置するメソッド
  /// Blokusのルールをすべて考慮しています
  mutating func placePiece(piece: Piece, at origin: Coordinate) throws {
    let shape = piece.transformedShape()
    
    // ピースの最終的な盤面上での座標を計算
    let finalCoords = shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
    
    // 基本チェック: ボード外、重複配置チェック
    for bc in finalCoords {
      guard isValidCoordinate(bc) else {
        throw PlacementError.outOfBounds
      }
      if case .occupied = cells[bc.y][bc.x] {
        throw PlacementError.cellOccupied
      }
    }
    
    let isFirstMove = (hasPlacedFirstPiece[piece.owner] == false)
    
    // 初回配置チェック: コーナーセルを必ず含む
    if isFirstMove {
      let corner = startingCorner(for: piece.owner)
      if !finalCoords.contains(corner) {
        throw PlacementError.firstMoveMustIncludeCorner
      }
    } else {
      // 2回目以降の配置チェック
      
      let playerCells = getPlayerCells(owner: piece.owner)
      var cornerTouch = false
      var edgeContactWithSelf = false
      
      for fc in finalCoords {
        // 斜め方向（角）チェック
        let neighborsDiagonal = [
          Coordinate(x: fc.x-1, y: fc.y-1),
          Coordinate(x: fc.x+1, y: fc.y-1),
          Coordinate(x: fc.x-1, y: fc.y+1),
          Coordinate(x: fc.x+1, y: fc.y+1)
        ]
        
        if neighborsDiagonal.contains(where: { playerCells.contains($0) }) {
          cornerTouch = true
        }
        
        // 辺方向チェック
        let neighborsEdge = [
          Coordinate(x: fc.x, y: fc.y-1),
          Coordinate(x: fc.x, y: fc.y+1),
          Coordinate(x: fc.x-1, y: fc.y),
          Coordinate(x: fc.x+1, y: fc.y)
        ]
        
        if neighborsEdge.contains(where: { playerCells.contains($0) }) {
          edgeContactWithSelf = true
        }
      }
      
      if cornerTouch == false {
        throw PlacementError.mustTouchOwnPieceByCorner
      }
      
      if edgeContactWithSelf == true {
        throw PlacementError.cannotShareEdgeWithOwnPiece
      }
    }
    
    // 配置確定
    for bc in finalCoords {
      cells[bc.y][bc.x] = .occupied(pieceID: piece.id, owner: piece.owner)
    }
    
    // 初手完了フラグ更新
    if isFirstMove {
      hasPlacedFirstPiece[piece.owner] = true
    }
  }
}

// MARK: - ハイライトの実装

extension Board {
  /// 現在のハイライトをすべてクリア
  mutating func clearHighlights() {
    highlightedCoordinates.removeAll()
  }
  
  /// 指定のpieceをat座標に置けるかチェックする
  /// 実際には配置せず、PlacementErrorの有無で判定
  func canPlacePiece(piece: Piece, at origin: Coordinate) -> Bool {
    let shape = piece.transformedShape()
    let finalCoords = shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
    
    // 基本チェック: ボード外、重複配置
    for bc in finalCoords {
      if !isValidCoordinate(bc) {
        return false
      }
      if case .occupied = cells[bc.y][bc.x] {
        return false
      }
    }
    
    let isFirstMove = (hasPlacedFirstPiece[piece.owner] == false)
    
    if isFirstMove {
      let corner = startingCorner(for: piece.owner)
      if !finalCoords.contains(corner) {
        return false
      }
    } else {
      // 2回目以降
      let playerCells = getPlayerCells(owner: piece.owner)
      var cornerTouch = false
      var edgeContactWithSelf = false
      
      for fc in finalCoords {
        let neighborsDiagonal = [
          Coordinate(x: fc.x-1, y: fc.y-1),
          Coordinate(x: fc.x+1, y: fc.y-1),
          Coordinate(x: fc.x-1, y: fc.y+1),
          Coordinate(x: fc.x+1, y: fc.y+1)
        ]
        if neighborsDiagonal.contains(where: { playerCells.contains($0) }) {
          cornerTouch = true
        }
        
        let neighborsEdge = [
          Coordinate(x: fc.x, y: fc.y-1),
          Coordinate(x: fc.x, y: fc.y+1),
          Coordinate(x: fc.x-1, y: fc.y),
          Coordinate(x: fc.x+1, y: fc.y)
        ]
        
        if neighborsEdge.contains(where: { playerCells.contains($0) }) {
          edgeContactWithSelf = true
        }
      }
      
      if cornerTouch == false {
        return false
      }
      if edgeContactWithSelf == true {
        return false
      }
    }
    
    return true
  }
  
  /// pieceを置ける場所をハイライトする
  mutating func highlightPossiblePlacements(for piece: Piece) {
    clearHighlights()
    for y in 0..<height {
      for x in 0..<width {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin) {
          // ピースの形状全体をハイライト
          let shape = piece.transformedShape()
          let finalCoords = shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
          highlightedCoordinates.formUnion(finalCoords)
        }
      }
    }
  }
}
