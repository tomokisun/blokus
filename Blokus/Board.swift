import SwiftUI

/// `Board` は Blokus のゲームボード全体を表す構造体です。
/// 固定サイズ（20x20）のセルを持ち、セルの状態を管理します。
/// 各プレイヤーの初期配置や、配置可能性チェック、ハイライト表示など、
struct Board {
  
  /// ボードの幅（列数）
  static let width = 20
  
  /// ボードの高さ（行数）
  static let height = 20
  
  /// ボード上のセルを管理する2次元配列。`Cell`型で状況を表します。
  var cells: [[Cell]] = Array(
    repeating: Array(repeating: Cell.empty, count: Board.width),
    count: Board.height
  )
  
  /// 配置可能な領域をハイライト表示するための座標集合
  var highlightedCoordinates: Set<Coordinate> = []
  
  // MARK: - Public Methods
  
  /// 指定したプレイヤーのスコアを返します。
  ///
  /// スコアは、そのプレイヤーがボード上に配置したセル数で計算されます。
  ///
  /// - Parameter player: スコアを取得したいプレイヤー色
  /// - Returns: 該当プレイヤーのセル数（スコア）
  func score(for player: PlayerColor) -> Int {
    let playerCells = getPlayerCells(owner: player)
    return playerCells.count
  }
  
  /// 指定した座標がボード上有効範囲内かを判定します。
  ///
  /// - Parameter c: 座標
  /// - Returns: 有効範囲内なら `true`、範囲外なら `false`
  func isValidCoordinate(_ c: Coordinate) -> Bool {
    return c.x >= 0 && c.x < Board.width && c.y >= 0 && c.y < Board.height
  }
  
  /// ピースをボードに配置します。
  /// 配置時には Blokus のルール（初回配置・2回目以降の配置条件など）を考慮します。
  ///
  /// - Parameters:
  ///   - piece: 配置するピース
  ///   - origin: ピースを配置する起点座標
  /// - Throws: `PlacementError` のいずれか（範囲外、セル占有済み、初回配置違反、角接触違反など）
  mutating func placePiece(piece: Piece, at origin: Coordinate) throws(PlacementError) {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    try validatePlacement(piece: piece, finalCoords: finalCoords)
    
    // 配置確定
    for bc in finalCoords {
      cells[bc.x][bc.y] = .occupied(owner: piece.owner)
    }
  }
  
  /// 指定のピースを特定の座標に置けるかどうか判定します（実際には置かない）。
  ///
  /// - Parameters:
  ///   - piece: 配置可否を判定するピース
  ///   - origin: 起点座標
  /// - Returns: 配置可能なら `true`、不可能なら `false`
  func canPlacePiece(piece: Piece, at origin: Coordinate) -> Bool {
    let finalCoords = computeFinalCoordinates(for: piece, at: origin)
    do {
      try validatePlacement(piece: piece, finalCoords: finalCoords)
      return true
    } catch {
      return false
    }
  }
  
  /// 指定したピースが配置可能な箇所をハイライトします。
  /// 配置可能な全ての座標を算出し、`highlightedCoordinates` に追加します。
  ///
  /// - Parameter piece: ハイライト対象のピース
  mutating func highlightPossiblePlacements(for piece: Piece) {
    clearHighlights()
    
    for y in 0..<Board.height {
      for x in 0..<Board.width {
        let origin = Coordinate(x: x, y: y)
        if canPlacePiece(piece: piece, at: origin) {
          let finalCoords = computeFinalCoordinates(for: piece, at: origin)
          highlightedCoordinates.formUnion(finalCoords)
        }
      }
    }
  }
  
  /// ハイライトをクリアし、`highlightedCoordinates` を空にします。
  mutating func clearHighlights() {
    highlightedCoordinates.removeAll()
  }
  
  // MARK: - Private Helpers
  
  /// ピースを指定座標に配置した場合のセル座標の一覧を取得します。
  ///
  /// - Parameters:
  ///   - piece: 配置対象のピース
  ///   - origin: 起点座標
  /// - Returns: ピースが占有する全セルの座標リスト
  private func computeFinalCoordinates(for piece: Piece, at origin: Coordinate) -> [Coordinate] {
    let shape = piece.transformedShape()
    return shape.map { Coordinate(x: origin.x + $0.x, y: origin.y + $0.y) }
  }
  
  /// ピース配置時のバリデーションを行います。
  ///
  /// - Parameters:
  ///   - piece: 配置対象のピース
  ///   - finalCoords: ピースが実際に占有するセル座標
  /// - Throws: `PlacementError` が発生する可能性があります。
  private func validatePlacement(piece: Piece, finalCoords: [Coordinate]) throws(PlacementError) {
    try checkBasicPlacementRules(finalCoords: finalCoords)
    let isFirstMove = !hasPlacedFirstPiece(for: piece.owner)
    
    if isFirstMove {
      try checkFirstPlacement(piece: piece, finalCoords: finalCoords)
    } else {
      try checkSubsequentPlacement(piece: piece, finalCoords: finalCoords)
    }
  }
  
  /// 基本的な配置チェック：ボード外・セル占有の有無を確認します。
  ///
  /// - Parameter finalCoords: ピースが占有するセル座標
  /// - Throws: `PlacementError.outOfBounds` または `PlacementError.cellOccupied`
  private func checkBasicPlacementRules(finalCoords: [Coordinate]) throws(PlacementError) {
    for bc in finalCoords {
      guard isValidCoordinate(bc) else {
        throw PlacementError.outOfBounds
      }
      if case .occupied = cells[bc.x][bc.y] {
        throw PlacementError.cellOccupied
      }
    }
  }
  
  /// 初回配置におけるチェック：プレイヤーの開始コーナーを含んでいるか確認します。
  ///
  /// - Parameters:
  ///   - piece: 配置対象のピース
  ///   - finalCoords: 占有セル座標
  /// - Throws: `PlacementError.firstMoveMustIncludeCorner` （開始コーナーを含んでいない場合）
  private func checkFirstPlacement(piece: Piece, finalCoords: [Coordinate]) throws(PlacementError) {
    let corner = Board.startingCorner(for: piece.owner)
    if !finalCoords.contains(corner) {
      throw PlacementError.firstMoveMustIncludeCorner
    }
  }
  
  /// 2回目以降の配置チェック：角接触必須、辺接触禁止のルールを検証します。
  ///
  /// - Parameters:
  ///   - piece: 配置対象のピース
  ///   - finalCoords: 占有セル座標
  /// - Throws:
  ///   - `PlacementError.mustTouchOwnPieceByCorner` （角接触なしの場合）
  ///   - `PlacementError.cannotShareEdgeWithOwnPiece` （辺で接触している場合）
  private func checkSubsequentPlacement(piece: Piece, finalCoords: [Coordinate]) throws(PlacementError) {
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
  
  /// 指定セルが斜め方向でプレイヤーのコマと接しているか確認します。
  ///
  /// - Parameters:
  ///   - fc: チェックするセル座標
  ///   - playerCells: プレイヤーが占有するセルの集合
  /// - Returns: 斜め（角）接触がある場合は `true`
  private func checkCornerTouch(fc: Coordinate, playerCells: Set<Coordinate>) -> Bool {
    let neighborsDiagonal = fc.diagonalNeighbors()
    return neighborsDiagonal.contains(where: { playerCells.contains($0) })
  }
  
  /// 指定セルが上下左右方向でプレイヤーのコマと接していないか確認します。
  ///
  /// - Parameters:
  ///   - fc: チェックするセル座標
  ///   - playerCells: プレイヤーが占有するセルの集合
  /// - Returns: 辺で接触がある場合は `true`
  private func checkEdgeContact(fc: Coordinate, playerCells: Set<Coordinate>) -> Bool {
    let neighborsEdge = fc.edgeNeighbors()
    return neighborsEdge.contains(where: { playerCells.contains($0) })
  }

  // MARK: - State Checking
  
  /// 指定したプレイヤーがすでに最初のピースを置いたか確認します。
  ///
  /// - Parameter player: チェックするプレイヤー色
  /// - Returns: 最初のピースが配置済みなら `true`、未配置なら `false`
  private func hasPlacedFirstPiece(for player: PlayerColor) -> Bool {
    let coordinate = Board.startingCorner(for: player)
    switch cells[coordinate.x][coordinate.y] {
    case .empty:
      return false
    case let .occupied(owner):
      return owner == player
    }
  }
  
  /// 指定プレイヤーが占有するセルすべてを取得します。
  ///
  /// - Parameter owner: プレイヤー色
  /// - Returns: 占有セル座標のセット
  private func getPlayerCells(owner: PlayerColor) -> Set<Coordinate> {
    var result = Set<Coordinate>()
    for y in 0..<Board.height {
      for x in 0..<Board.width {
        if case let .occupied(cellOwner) = cells[x][y], cellOwner == owner {
          result.insert(Coordinate(x: x, y: y))
        }
      }
    }
    return result
  }
  
  // MARK: - Static Utilities
  
  /// 各プレイヤーの開始コーナー座標を返します。
  ///
  /// - Parameter player: コーナーを取得したいプレイヤー色
  /// - Returns: プレイヤー開始地点の座標
  static func startingCorner(for player: PlayerColor) -> Coordinate {
    switch player {
    case .red:
      return Coordinate(x: 0, y: 0)
    case .blue:
      return Coordinate(x: Board.width - 1, y: 0)
    case .green:
      return Coordinate(x: Board.width - 1, y: Board.height - 1)
    case .yellow:
      return Coordinate(x: 0, y: Board.height - 1)
    }
  }
}

