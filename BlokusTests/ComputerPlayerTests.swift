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
    var pieces = [makeSingleCellPiece(owner: .red)]
    
    var cpu = ComputerPlayer(owner: .red, level: .easy)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    // redは初手で(0,0)が配置できるはず
    // 初手がうまくいっていれば piecesから削除されている
    #expect(pieces.isEmpty == true)
    #expect(board.cells[0][0] == .occupied(owner: .red))
  }
  
  @Test
  func testCPUNoMovesPass() async throws {
    var board = Board()
    // redはピースを持っていない
    var pieces: [Piece] = []
    
    var cpu = ComputerPlayer(owner: .red, level: .easy)
    // 出力確認は難しいが、ここではpiecesやboardが変わらないことを確認
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    #expect(pieces.isEmpty == true)
    // 何も置かれていない
    #expect(board.cells[0][0] == Cell.empty)
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
    var cpu = ComputerPlayer(owner: .red, level: .easy)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    // 2手目は(1,1)等、斜め接触できる位置に置くはず
    // 場所はCPUロジックが探すので(1,1)を期待
    #expect(pieces.isEmpty == true)
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
    var cpu = ComputerPlayer(owner: .red, level: .normal)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    // normalレベルでは大きいピースを優先して試すため、bigPieceが最初に配置される可能性が高い
    // （ロジック上、bigPieceが最初に試されるはず）
    // bigPieceが(0,0)を含んで水平に配置されることで初手成功
    #expect(pieces.count == 2) // bigPieceが消えたはず
    
    // 次の手でmediumPieceかsmallPieceを置いてみる(オプション)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    // mediumPieceまたはsmallPieceが配置されているはず
    #expect(pieces.count == 1) // もう一つ消える
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
    var pieces: [Piece] = [
      makeSingleCellPiece(owner: .red),
      makeSingleCellPiece(owner: .red)
    ]
    
    var cpu = ComputerPlayer(owner: .red, level: .easy)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    // 置けないのでパス。piecesはそのまま
    #expect(pieces.count == 2)
  }
  
  @Test
  func testCPUPieceRemovedAfterPlacement() async throws {
    // CPUが成功して配置した場合、そのピースがpiecesから削除されるか確認
    var board = Board()
    // redの初手用ピース
    let p = makeSingleCellPiece(owner: .red)
    var pieces = [p]
    
    var cpu = ComputerPlayer(owner: .red, level: .easy)
    cpu.performCPUMove(board: &board, pieces: &pieces)
    
    // 初手成功でpiecesは空になる
    #expect(pieces.isEmpty == true)
    #expect(board.cells[0][0] == Cell.occupied(owner: .red))
  }
}
