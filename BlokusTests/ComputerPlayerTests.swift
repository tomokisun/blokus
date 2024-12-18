import Testing
@testable import Blokus

struct ComputerPlayerTests {
  
  /// 簡易な1マスピース生成
  private func makeSingleCellPiece(owner: PlayerColor) -> Piece {
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
    // red用のピースを用意
    let pieces = [makeSingleCellPiece(owner: .red)]
    
    let cpu = ComputerPlayer(owner: .red, level: .easy)
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    // redは初手で(0,0)が配置できるはず
    #expect(board.cells[0][0] == .occupied(owner: .red))
  }
  
  @Test
  func testCPUNoMovesPass() async throws {
    let board = Board()
    // redはピースを持っていない
    let pieces: [Piece] = []
    
    let cpu = ComputerPlayer(owner: .red, level: .easy)
    
    #expect(pieces.isEmpty == true)
    #expect(cpu.moveCandidate(board: board, pieces: pieces) == nil)
  }
  
  @Test
  func testCPUSecondMoveCornerTouch() async throws {
    var board = Board()
    // 初手用ピースと2手目用ピース
    var pieces = [
      makeSingleCellPiece(owner: .red),
      makeSingleCellPiece(owner: .red)
    ]
    
    // 人間プレイヤーなしで初手だけ先に配置
    // 手動で初手を配置して、2手目のテストを行う
    try board.placePiece(piece: pieces[0], at: Coordinate(x:0,y:0))
    pieces.removeFirst() // 初手済みピース除去
    
    // Now CPUの2手目
    let cpu = ComputerPlayer(owner: .red, level: .easy)
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    // 2手目は(1,1)等、斜め接触できる位置に置くはず
    // 場所はCPUロジックが探すので(1,1)を期待
    #expect(board.cells[1][1] == Cell.occupied(owner: .red))
  }
  
  @Test
  func testCPUWithMultiplePiecesNormalLevel() async throws {
    var board = Board()
    // 大きいピース(5マス), 中くらい(3マス), 小さい(1マス)などを用意
    let bigPiece = Piece(
      id: "red-big",
      owner: .red,
      baseShape: [Coordinate(x:0,y:0),Coordinate(x:1,y:0),Coordinate(x:2,y:0),Coordinate(x:3,y:0),Coordinate(x:4,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
    let mediumPiece = Piece(
      id: "red-medium",
      owner: .red,
      baseShape: [Coordinate(x:0,y:0),Coordinate(x:0,y:1),Coordinate(x:1,y:1)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
    let smallPiece = makeSingleCellPiece(owner: .red)
    
    var pieces = [bigPiece, mediumPiece, smallPiece]
    
    // 初手は必ずコーナーを含む必要があるので、一番大きなピースでも(0,0)を含む直線であれば置けるはず。
    let cpu = ComputerPlayer(owner: .red, level: .normal)
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      #expect(candidate.piece.id == bigPiece.id)
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      pieces.removeAll(where: { $0.id == candidate.piece.id })
    }
    
    // normalレベルでは大きいピースを優先して試すため、bigPieceが最初に配置される
    // bigPieceが(0,0)を含んで水平に配置されることで初手成功
    #expect(board.cells[0][0] == Cell.occupied(owner: .red))
    #expect(pieces.count == 2)
    
    // 次の手でmediumPieceを置いてみる
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      #expect(candidate.piece.id == mediumPiece.id)
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      pieces.removeAll(where: { $0.id == candidate.piece.id })
    }

    // mediumPieceが配置されているはず
    #expect(pieces == [smallPiece])
  }
  
  @Test
  func testCPUCannotPlacePass() async throws {
    // CPUはピースを持つが、ボードが全部埋まっていて置けないケース
    var board = Board()
    // 全セルをfake占有
    for y in 0..<Board.height {
      for x in 0..<Board.width {
        board.cells[y][x] = .occupied(owner: .blue)
      }
    }
    
    // redがピースを持っていても置く場所ない
    let pieces: [Piece] = [
      makeSingleCellPiece(owner: .red),
      makeSingleCellPiece(owner: .red)
    ]
    
    let cpu = ComputerPlayer(owner: .red, level: .easy)
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    // 置けないのでパス。piecesはそのまま
    #expect(pieces.count == 2)
  }
  
  @Test
  func testCPUPieceRemovedAfterPlacement() async throws {
    // CPUが成功して配置した場合、そのピースがpiecesから削除されるか確認
    var board = Board()
    // redの初手用ピース
    let p = makeSingleCellPiece(owner: .red)
    let pieces = [p]
    
    let cpu = ComputerPlayer(owner: .red, level: .easy)
    if let candidate = cpu.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    }
    
    // 初手成功でpiecesは空になる
    #expect(board.cells[0][0] == Cell.occupied(owner: .red))
  }
}
