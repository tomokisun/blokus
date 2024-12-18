import SwiftUI

/// Blokusのゲームボード全体を表す構造体
struct Board: Codable {
  static let width = 20
  static let height = 20

  // ハイライト用の座標集合を追加
  var highlightedCoordinates: Set<Coordinate> = []

  var cells: [[Cell]] = Array(
    repeating: Array(repeating: Cell.empty, count: Self.width),
    count: Self.height
  )
  
  /// 指定した座標がボード上に存在するかをチェック
  func isValidCoordinate(_ c: Coordinate) -> Bool {
    return c.x >= 0 && c.x < Self.width && c.y >= 0 && c.y < Self.height
  }
  
  /// 各プレイヤーの開始コーナーを返す
  static func startingCorner(for player: PlayerColor) -> Coordinate {
    switch player {
    case .red:
      return Coordinate(x: 0, y: 0)
    case .blue:
      return Coordinate(x: Self.width - 1, y: 0)
    case .green:
      return Coordinate(x: Self.width - 1, y: Self.height - 1)
    case .yellow:
      return Coordinate(x: 0, y: Self.height - 1)
    }
  }
  
  func hasPlacedFirstPiece(for player: PlayerColor) -> Bool {
    let coordinate = Board.startingCorner(for: player)
    switch cells[coordinate.y][coordinate.x] {
    case .empty:
      return false
    case let .occupied(_, owner):
      return owner == player
    }
  }
  
  func getPlayerCells(owner: PlayerColor) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for y in 0..<Self.height {
      for x in 0..<Self.width {
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
    
    let isFirstMove = !hasPlacedFirstPiece(for: piece.owner)
    
    // 初回配置チェック: コーナーセルを必ず含む
    if isFirstMove {
      let corner = Self.startingCorner(for: piece.owner)
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
    
    let isFirstMove = !hasPlacedFirstPiece(for: piece.owner)
    
    if isFirstMove {
      let corner = Self.startingCorner(for: piece.owner)
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
    for y in 0..<Self.height {
      for x in 0..<Self.width {
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
