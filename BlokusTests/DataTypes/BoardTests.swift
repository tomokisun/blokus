import Testing
@testable import Blokus

struct BoardTests {
  
  /// 単純な1マスのピースを作るためのヘルパー
  private func makeSingleCellPiece(owner: PlayerColor) -> Piece {
    // (0,0)をbaseShapeとし、初期状態は未回転・非反転
    return Piece(
      id: "\(owner.rawValue)-single",
      owner: owner,
      baseShape: [Coordinate(x: 0, y: 0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  @Test
  func testPlacePieceOutOfBounds() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    
    // 盤外(負座標)に置こうとする
    let invalidOrigin = Coordinate(x: -1, y: -1)
    #expect {
      try board.placePiece(piece: piece, at: invalidOrigin)
    } throws: { error in
      guard let e = error as? PlacementError else {
        return false
      }
      return e == .outOfBounds
    }
  }
  
  @Test
  func testFirstMoveMustIncludeCorner_Success() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .red)
    
    // Redの開始コーナーは(0,0)
    let origin = Coordinate(x: 0, y: 0)
    try board.placePiece(piece: piece, at: origin)
    
    // 配置成功後、(0,0)はredのピースになっているはず
    #expect(board.cells[0][0] == Cell.occupied(owner: PlayerColor.red))
  }
  
  @Test
  func testFirstMoveMustIncludeCorner_Failure() async throws {
    var board = Board()
    let piece = makeSingleCellPiece(owner: .blue)
    
    // Blueの開始コーナーは(x: Board.width-1, y:0) = (19, 0)
    // コーナーを含まない (0,0)にBlueが最初の駒を置くのは不正
    let invalidOrigin = Coordinate(x: 0, y: 0)
    
    #expect {
      try board.placePiece(piece: piece, at: invalidOrigin)
    } throws: { error in
      guard let e = error as? PlacementError else {
        return false
      }
      return e == .firstMoveMustIncludeCorner
    }
  }
  
  @Test
  func testSubsequentPlacementCornerTouchSuccess() async throws {
    var board = Board()
    let piece1 = makeSingleCellPiece(owner: .red)
    
    // 初手: redは(0,0)に配置
    try board.placePiece(piece: piece1, at: Coordinate(x: 0, y: 0))
    
    // 2手目として、redがもう1つの1マスピースを(1,1)に置くとする
    // (1,1)は(0,0)と斜めで接しているため、角接触OK
    let piece2 = makeSingleCellPiece(owner: .red)
    try board.placePiece(piece: piece2, at: Coordinate(x: 1, y: 1))
    
    // (1,1)にredのピースが置かれているはず
    #expect(board.cells[1][1] == Cell.occupied(owner: PlayerColor.red))
  }
  
  @Test
  func testSubsequentPlacementTouchOwnPieceByCornerFailure() async throws {
    var board = Board()
    let piece1 = makeSingleCellPiece(owner: .yellow)
    
    // 初手: yellowは(0, 19)に配置 (左下コーナー)
    try board.placePiece(piece: piece1, at: Coordinate(x: 0, y: 19))
    
    // (0,19)にyellowのピースが置かれているはず
    #expect(board.cells[0][19] == Cell.occupied(owner: PlayerColor.yellow))
    
    // 次の配置で、yellowが(1, 19)に置こうとする
    // これは初手の駒(0,19)と辺で隣接してしまうためNG
    let piece2 = makeSingleCellPiece(owner: .yellow)
    
    #expect {
      try board.placePiece(piece: piece2, at: Coordinate(x: 1, y: 19))
    } throws: { error in
      guard let e = error as? PlacementError else {
        return false
      }
      return e == .mustTouchOwnPieceByCorner
    }
  }
}
