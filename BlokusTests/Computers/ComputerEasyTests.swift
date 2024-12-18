import Testing
@testable import Blokus

struct ComputerEasyTests {
  private func makeSingleCellPiece(owner: PlayerColor) -> Piece {
    Piece(
      id: "\(owner.rawValue)-single",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  @Test
  func testMoveCandidate_withAvailablePieces_returnsCandidate() async {
    let board = Board()
    let owner: PlayerColor = .red
    let pieces = [makeSingleCellPiece(owner: owner)]
    let computer = ComputerEasy(owner: owner)
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    
    #expect(candidate != nil)
    #expect(candidate?.piece.owner == owner)
  }
  
  @Test
  func testMoveCandidate_withNoOwnedPieces_returnsNil() async {
    let board = Board()
    let owner: PlayerColor = .blue
    // オーナーredのピースしかないため、blueには何もない状況
    let pieces = [makeSingleCellPiece(owner: .red)]
    let computer = ComputerEasy(owner: owner)
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    
    #expect(candidate == nil)
  }
  
  @Test
  func testMoveCandidate_withNoPlacableLocations_returnsNil() async {
    var board = Board()
    let owner: PlayerColor = .red
    let pieces = [makeSingleCellPiece(owner: owner)]
    let computer = ComputerEasy(owner: owner)
    
    // 全てのセルをオーナーblueで埋める(占有状態)ことでredのコマが置けない状態を作る
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        board.cells[x][y] = .occupied(owner: .blue)
      }
    }
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    
    #expect(candidate == nil)
  }
}
