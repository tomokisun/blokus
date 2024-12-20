import Testing
@testable import Blokus

struct ComputerHardTests {
  private func makeSingleCellPiece(owner: Player, id: String = "single") -> Piece {
    Piece(
      id: "\(owner.rawValue)-\(id)",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  private func makeLinearPiece(owner: Player, length: Int, id: String) -> Piece {
    let shape = (0..<length).map { Coordinate(x: $0, y: 0) }
    return Piece(
      id: "\(owner.rawValue)-\(id)",
      owner: owner,
      baseShape: shape,
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  @Test
  func testHardNoPieces() async {
    let board = Board()
    let owner: Player = .red
    let pieces: [Piece] = []
    let computer = ComputerHard(owner: owner)
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    #expect(candidate == nil, "ピースがなければパス")
  }
  
  @Test
  func testHardNoPlaceableLocations() async {
    var board = Board()
    let owner: Player = .red
    let pieces = [makeSingleCellPiece(owner: owner)]
    let computer = ComputerHard(owner: owner)
    
    // 全てのセルをオーナーblueで埋めてredが置けない状態にする
    for x in 0..<Board.width {
      for y in 0..<Board.height {
        board.cells[x][y] = .occupied(owner: .blue)
      }
    }
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    #expect(candidate == nil, "置く場所がなければパス")
  }
  
  @Test
  func testHardPrefersLargerPieces() async throws {
    var board = Board()
    let owner = Player.red
    // 大きいピースと小さいピース、両方用意
    let bigPiece = makeLinearPiece(owner: owner, length: 5, id: "big")   // 5セル
    let smallPiece = makeSingleCellPiece(owner: owner, id: "small")     // 1セル
    
    let computer = ComputerHard(owner: owner)
    let pieces = [bigPiece, smallPiece]
    
    // 初手
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      #expect(candidate.piece.id == bigPiece.id, "サイズが大きいbigPieceが選ばれるはず")
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    } else {
      Issue.record("候補があるのに取得できなかった")
    }
  }
  
  @Test
  func testHardMultiplePiecesWithDifferentShapes() async throws {
    var board = Board()
    let owner = Player.red
    
    // 先に1つ配置しておく
    let initialPiece = makeSingleCellPiece(owner: owner, id: "initial")
    try board.placePiece(piece: initialPiece, at: Coordinate(x:0, y:0))
    
    // 大きいピースと中ぐらいのピース、さらに小さいピースを用意
    // Hardはサイズ優先+角接触優先
    let bigPiece = makeLinearPiece(owner: owner, length: 5, id: "big")
    let mediumPiece = makeLinearPiece(owner: owner, length: 3, id: "medium")
    let smallPiece = makeSingleCellPiece(owner: owner, id: "small")
    
    let pieces = [bigPiece, mediumPiece, smallPiece]
    let computer = ComputerHard(owner: owner)
    
    // 初手済みなので、2手目
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      // bigPieceが選ばれるはず（サイズ最大）
      #expect(candidate.piece.id == bigPiece.id, "大きなコマで斜め接触可能性が高いものが選ばれる")
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
    } else {
      Issue.record("候補があるはずなのにnilが返った")
    }
  }
}
