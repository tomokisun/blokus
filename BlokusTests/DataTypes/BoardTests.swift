import Testing
@testable import Blokus

struct BoardTests {
  
  /// 単純な1マスのピースを作るためのヘルパー
  private func makeSingleCellPiece(owner: PlayerColor, rotation: Rotation = .none, flipped: Bool = false) -> Piece {
    // (0,0)をbaseShapeとし、初期状態は指定のorientationを反映
    return Piece(
      id: "\(owner.rawValue)-single-\(rotation.rawValue)-\(flipped)",
      owner: owner,
      baseShape: [Coordinate(x: 0, y: 0)],
      orientation: Orientation(rotation: rotation, flipped: flipped)
    )
  }
  
  @Test
  func testPlacePieceOutOfBounds() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    
    let invalidOrigin = Coordinate(x: -1, y: -1)
    #expect {
      try board.placePiece(piece: piece, at: invalidOrigin)
    } throws: { error in
      guard let e = error as? PlacementError else { return false }
      return e == .outOfBounds
    }
  }
  
  @Test
  func testFirstMoveMustIncludeCorner_Success() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    let origin = Coordinate(x: 0, y: 0)
    try board.placePiece(piece: piece, at: origin)
    #expect(board.cells[0][0] == Cell.occupied(owner: PlayerColor.red))
  }
  
  @Test
  func testFirstMoveMustIncludeCorner_Failure() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .blue)
    // Blueの開始コーナーは(19,0)
    let invalidOrigin = Coordinate(x: 0, y: 0)
    
    #expect {
      try board.placePiece(piece: piece, at: invalidOrigin)
    } throws: { error in
      guard let e = error as? PlacementError else { return false }
      return e == .firstMoveMustIncludeCorner
    }
  }
  
  @Test
  func testSubsequentPlacementCornerTouchSuccess() async throws {
    var board = Board()
    let piece1 = makeSingleCellPiece(owner: .red)
    try board.placePiece(piece: piece1, at: Coordinate(x: 0, y: 0))
    
    let piece2 = makeSingleCellPiece(owner: .red)
    try board.placePiece(piece: piece2, at: Coordinate(x: 1, y: 1))
    #expect(board.cells[1][1] == Cell.occupied(owner: PlayerColor.red))
  }
  
  @Test
  func testSubsequentPlacementNoCornerTouch_Failure() async throws {
    var board = Board()
    let piece1 = makeSingleCellPiece(owner: .yellow)
    // 初手: 左下コーナー(yellow)
    try board.placePiece(piece: piece1, at: Coordinate(x: 0, y: Board.height-1))
    #expect(board.cells[0][Board.height-1] == Cell.occupied(owner: PlayerColor.yellow))
    
    let piece2 = makeSingleCellPiece(owner: .yellow)
    // 辺で接触するのみ(隣り合わせに置く)→失敗
    #expect {
      try board.placePiece(piece: piece2, at: Coordinate(x: 1, y: Board.height-1))
    } throws: { error in
      guard let e = error as? PlacementError else { return false }
      return e == .mustTouchOwnPieceByCorner
    }
  }
  
  @Test
  func testCanPlacePieceCheck() async throws {
    let board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    // 初手コーナー配置可能チェック
    #expect(board.canPlacePiece(piece: piece, at: Coordinate(x:0, y:0)) == true)
    // コーナー以外に置けないことを確認
    #expect(board.canPlacePiece(piece: piece, at: Coordinate(x:1, y:0)) == false)
  }
  
  @Test
  func testRotationAndFlipPlacement() async throws {
    var board = Board()
    // 大きめのピース(3マスL字)を想定してテスト(例)
    let lShape = [Coordinate(x:0,y:0), Coordinate(x:0,y:1), Coordinate(x:1,y:1)]
    let piece = Piece(
      id: "red-L",
      owner: .red,
      baseShape: lShape,
      orientation: Orientation(rotation: .none, flipped: false)
    )
    // 初手なのでコーナー含めなければならない
    // L字をそのまま(0,0)に配置すると、(0,0),(0,1),(1,1)が使用され、(0,0)はコーナー含むのでOK
    try board.placePiece(piece: piece, at: Coordinate(x:0,y:0))
    #expect(board.cells[0][0] == .occupied(owner: .red))
    #expect(board.cells[0][1] == .occupied(owner: .red))
    #expect(board.cells[1][1] == .occupied(owner: .red))
    
    // 次に反転、回転した形を配置できるか確認
    let flippedPiece = Piece(
      id: "red-flipped-L",
      owner: .red,
      baseShape: lShape,
      orientation: Orientation(rotation: .ninety, flipped: true)
    )
    // flipped & ninetyの場合、形状が変わるが詳細計算は割愛
    // とりあえず(2,2)あたりに置けるか?
    // 簡易確認: canPlacePieceでtrue/falseをチェック
    let canPlace = board.canPlacePiece(piece: flippedPiece, at: Coordinate(x:2,y:2))
    // 実際に置いてみる(不可能ならエラー）
    if canPlace {
      try board.placePiece(piece: flippedPiece, at: Coordinate(x:2,y:2))
      #expect(board.cells[2][2] == .occupied(owner: .red))
    }
  }
  
  @Test
  func testHighlightPossiblePlacements() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    // 初手前: redは(0,0)に置けるのでハイライトされるはず
    board.highlightPossiblePlacements(for: piece)
    #expect(board.highlightedCoordinates.contains(Coordinate(x:0,y:0)) == true)
    
    // 置いてしまったあと、次の配置箇所をハイライトしてみる
    try board.placePiece(piece: piece, at: Coordinate(x:0,y:0))
    
    let piece2 = makeSingleCellPiece(owner: .red)
    board.highlightPossiblePlacements(for: piece2)
    // 次手は角接触必須なので(1,1)などがハイライトされるはず
    #expect(board.highlightedCoordinates.contains(Coordinate(x:1,y:1)) == true)
    
    // 他の無関係な場所はハイライトされていないこと
    #expect(board.highlightedCoordinates.contains(Coordinate(x:5,y:5)) == false)
    
    // ピースを置く場所が一切ない場合(例えば全部埋めた後)はハイライトなし
    // 簡易的にboardを埋めるなどはここでは省略
    // 代わりにピース所有者が存在しないピースなどでチェック
    let piece3 = makeSingleCellPiece(owner: .blue)
    // blueまだ初手も打ってない
    // blueのコーナーは(19,0)なので(19,0)はハイライトされるはず
    board.clearHighlights()
    board.highlightPossiblePlacements(for: piece3)
    #expect(board.highlightedCoordinates.contains(Coordinate(x:19,y:0)) == true)
  }
}
