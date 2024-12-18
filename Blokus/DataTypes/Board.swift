import SwiftUI

/// Blokusのゲームボード全体を表す構造体
struct Board: Codable {
  static let width = 20
  static let height = 20
  
  var cells: [[Cell]] = Array(
    repeating: Array(repeating: Cell.empty, count: Self.width),
    count: Self.height
  )
  
  // ハイライト用の座標集合
  var highlightedCoordinates: Set<Coordinate> = []
  
  // MARK: - Public Methods
  
  /// 指定した座標がボード上に存在するかをチェック
  func isValidCoordinate(_ c: Coordinate) -> Bool {
    return c.x >= 0 && c.x < Self.width && c.y >= 0 && c.y < Self.height
  }
  
  /// ピースを配置するメソッド
  /// Blokusのルールをすべて考慮しています
  mutating func placePiece(piece: Piece, at origin: Coordinate) throws {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    
    try validatePlacement(piece: piece, finalCoords: finalCoords)
    
    // 配置確定
    for bc in finalCoords {
      cells[bc.y][bc.x] = .occupied(owner: piece.owner)
    }
  }
  
  /// pieceを置けるかチェック（本当に置かず、ルール的にOKか判定）
  func canPlacePiece(piece: Piece, at origin: Coordinate) -> Bool {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    do {
      try validatePlacement(piece: piece, finalCoords: finalCoords)
      return true
    } catch {
      return false
    }
  }
  
  /// ピースを置ける場所をハイライト表示
  mutating func highlightPossiblePlacements(for piece: Piece) {
    clearHighlights()
    
    for y in 0..<Self.height {
      for x in 0..<Self.width {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin) {
          let finalCoords = computeFinalCoordinates(for: piece, at: origin)
          highlightedCoordinates.formUnion(finalCoords)
        }
      }
    }
  }
  
  /// ハイライトをクリア
  mutating func clearHighlights() {
    highlightedCoordinates.removeAll()
  }
  
  // MARK: - Private Helpers
  
  private func computeFinalCoordinates(for piece: Piece, at origin: Coordinate) -> [Coordinate] {
    let shape = piece.transformedShape()
    return shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
  }
  
  /// 配置可否判定（エラー発生時はスロー）
  private func validatePlacement(piece: Piece, finalCoords: [Coordinate]) throws {
    try checkBasicPlacementRules(finalCoords: finalCoords)
    let isFirstMove = !hasPlacedFirstPiece(for: piece.owner)
    
    if isFirstMove {
      try checkFirstPlacement(piece: piece, finalCoords: finalCoords)
    } else {
      try checkSubsequentPlacement(piece: piece, finalCoords: finalCoords)
    }
  }
  
  /// 基本的な配置チェック（ボード外、重複配置）
  private func checkBasicPlacementRules(finalCoords: [Coordinate]) throws {
    for bc in finalCoords {
      guard isValidCoordinate(bc) else {
        throw PlacementError.outOfBounds
      }
      if case .occupied = cells[bc.y][bc.x] {
        throw PlacementError.cellOccupied
      }
    }
  }
  
  /// 初回配置チェック（コーナーセルを含んでいるか）
  private func checkFirstPlacement(piece: Piece, finalCoords: [Coordinate]) throws {
    let corner = Board.startingCorner(for: piece.owner)
    if !finalCoords.contains(corner) {
      throw PlacementError.firstMoveMustIncludeCorner
    }
  }
  
  /// 2回目以降の配置チェック（角接触必須、辺接触禁止）
  private func checkSubsequentPlacement(piece: Piece, finalCoords: [Coordinate]) throws {
    let playerCells = getPlayerCells(owner: piece.owner)
    
    var cornerTouch = false
    var edgeContactWithSelf = false
    
    for fc in finalCoords {
      if checkCornerTouch(fc: fc, playerCells: playerCells) {
        cornerTouch = true
      }
      if checkEdgeContact(fc: fc, playerCells: playerCells) {
        edgeContactWithSelf = true
      }
    }
    
    if !cornerTouch {
      throw PlacementError.mustTouchOwnPieceByCorner
    }
    if edgeContactWithSelf {
      throw PlacementError.cannotShareEdgeWithOwnPiece
    }
  }
  
  /// 角接触チェック
  private func checkCornerTouch(fc: Coordinate, playerCells: Set<Coordinate>) -> Bool {
    let neighborsDiagonal = diagonalNeighbors(of: fc)
    return neighborsDiagonal.contains(where: { playerCells.contains($0) })
  }
  
  /// 辺接触チェック
  private func checkEdgeContact(fc: Coordinate, playerCells: Set<Coordinate>) -> Bool {
    let neighborsEdge = edgeNeighbors(of: fc)
    return neighborsEdge.contains(where: { playerCells.contains($0) })
  }
  
  private func diagonalNeighbors(of coord: Coordinate) -> [Coordinate] {
    return [
      Coordinate(x: coord.x-1, y: coord.y-1),
      Coordinate(x: coord.x+1, y: coord.y-1),
      Coordinate(x: coord.x-1, y: coord.y+1),
      Coordinate(x: coord.x+1, y: coord.y+1)
    ]
  }
  
  private func edgeNeighbors(of coord: Coordinate) -> [Coordinate] {
    return [
      Coordinate(x: coord.x, y: coord.y-1),
      Coordinate(x: coord.x, y: coord.y+1),
      Coordinate(x: coord.x-1, y: coord.y),
      Coordinate(x: coord.x+1, y: coord.y)
    ]
  }
  
  // MARK: - State Checking
  
  private func hasPlacedFirstPiece(for player: PlayerColor) -> Bool {
    let coordinate = Board.startingCorner(for: player)
    switch cells[coordinate.y][coordinate.x] {
    case .empty:
      return false
    case let .occupied(owner):
      return owner == player
    }
  }
  
  private func getPlayerCells(owner: PlayerColor) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for y in 0..<Self.height {
      for x in 0..<Self.width {
        if case let .occupied(cellOwner) = cells[y][x], cellOwner == owner {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
  }
  
  // MARK: - Static Utilities
  
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
}
