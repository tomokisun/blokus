import Testing
@testable import Blokus

struct ComputerNormalTests {
  private func makeSingleCellPiece(owner: Player) -> Piece {
    Piece(
      id: "\(owner.rawValue)-single",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  @Test
  func testCPUFirstMove() async throws {
    var board = Board()
    let owner: Player = .red
    let pieces = [makeSingleCellPiece(owner: owner)]
    let computer = ComputerNormal(owner: .red)
    
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    #expect(board.cells[0][0] == Cell(owner: owner), "初手で(0,0)に配置されるはず")
  }
  
  @Test
  func testCPUNoMovesPass() async throws {
    let board = Board()
    let pieces: [Piece] = []
    let computer = ComputerNormal(owner: .red)
    
    #expect(await computer.moveCandidate(board: board, pieces: pieces) == nil, "Pieceがないのでパス")
  }
  
  @Test
  func testCPUSecondMoveCornerTouch() async throws {
    var board = Board()
    let owner = Player.red
    var pieces = [
      makeSingleCellPiece(owner: owner),
      makeSingleCellPiece(owner: owner)
    ]
    
    // 人間プレイヤーなしで初手だけ先に配置
    // 手動で初手を配置して、2手目のテストを行う
    try board.placePiece(piece: pieces[0], at: Coordinate(x:0,y:0))
    pieces.removeFirst() // 初手済みピース除去
    
    // Now CPUの2手目
    let computer = ComputerNormal(owner: owner)
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    #expect(board.cells[1][1] == Cell(owner: owner), "2手目で(1,1)に配置される")
  }
  
  @Test
  func testCPUWithMultiplePiecesNormalLevel() async throws {
    var board = Board()
    let owner = Player.red
    // 5 cell piece
    let bigPiece = Piece(
      id: "red-big",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0),Coordinate(x:1,y:0),Coordinate(x:2,y:0),Coordinate(x:3,y:0),Coordinate(x:4,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
    // 3cell piece
    let mediumPiece = Piece(
      id: "red-medium",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0),Coordinate(x:0,y:1),Coordinate(x:1,y:1)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
    // 1 cell piece
    let smallPiece = makeSingleCellPiece(owner: owner)
    
    var pieces = [bigPiece, mediumPiece, smallPiece]
    
    // 初手
    let computer = ComputerNormal(owner: owner)
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      #expect(candidate.piece.id == bigPiece.id, "bigPieceが選ばれる")
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      pieces.removeAll(where: { $0.id == candidate.piece.id })
    }
    
    #expect(board.cells[0][0] == Cell(owner: owner))
    #expect(pieces.count == 2)
    
    // 2手目
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      #expect(candidate.piece.id == mediumPiece.id, "mediumPieceが選ばれる")
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      pieces.removeAll(where: { $0.id == candidate.piece.id })
    }

    #expect(pieces == [smallPiece], "smallPieceのみ残っている")
  }
  
  @Test
  func testCPUCannotPlacePass() async throws {
    // CPUはピースを持つが、ボードが全部埋まっていて置けないケース
    var board = Board()
    let owner = Player.red
    // 全セルをfake占有
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        board.cells[x][y] = Cell(owner: .blue)
      }
    }
    
    // redがピースを持っていても置く場所ない
    let pieces: [Piece] = [
      makeSingleCellPiece(owner: owner),
      makeSingleCellPiece(owner: owner)
    ]
    
    let computer = ComputerNormal(owner: owner)
    #expect(await computer.moveCandidate(board: board, pieces: pieces) == nil, "置けないのでパス")
  }
}
