import Testing
@testable import Blokus

struct ComputerHardTests {
  private func makeSingleCellPiece(owner: PlayerColor, id: String = "single") -> Piece {
    Piece(
      id: "\(owner.rawValue)-\(id)",
      owner: owner,
      baseShape: [Coordinate(x:0,y:0)],
      orientation: Orientation(rotation: .none, flipped: false)
    )
  }
  
  private func makeLinearPiece(owner: PlayerColor, length: Int, id: String) -> Piece {
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
    let owner: PlayerColor = .red
    let pieces: [Piece] = []
    let computer = ComputerHard(owner: owner)
    
    let candidate = await computer.moveCandidate(board: board, pieces: pieces)
    #expect(candidate == nil, "ピースがなければパス")
  }
  
  @Test
  func testHardNoPlaceableLocations() async {
    var board = Board()
    let owner: PlayerColor = .red
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
    let owner = PlayerColor.red
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
  func testHardPrefersDiagonalContacts() async throws {
    var board = Board()
    let owner = PlayerColor.red
    
    // まず初手で1セルのコマを(0,0)に配置して、オーナーredのセルを盤面に用意
    let initialPiece = makeSingleCellPiece(owner: owner, id: "initial")
    try board.placePiece(piece: initialPiece, at: Coordinate(x:0, y:0))
    
    // 次に、2つのコマを用意：
    // 1. mediumPiece: 3セル、横一列
    // 2. smallPiece: 1セル
    // 両方とも置けるが、"mediumPiece" はより大きいコマであるため優先度は同等か高い。
    // さらに、"mediumPiece" が(1,1)あたりに配置できれば、(0,0)にあるコマと斜めで接触する（角接触が増える）。
    
    let mediumPiece = makeLinearPiece(owner: owner, length: 3, id: "medium") // 3セル
    let smallPiece = makeSingleCellPiece(owner: owner, id: "small")
    let pieces = [mediumPiece, smallPiece]
    
    // Hardロジックで、mediumPieceを斜め接触の多い位置に置くことを期待
    let computer = ComputerHard(owner: owner)
    
    // 候補手を取得
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      // mediumPieceが選ばれるはず（サイズが大きく斜め接触も狙える）
      #expect(candidate.piece.id == mediumPiece.id, "Hardは大きいコマかつ角接触を増やせるコマを優先する")
      
      // 配置して確認
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      
      // mediumPieceが(1,1)あたりに置かれているかチェック
      // Hardのロジックでは候補の中で最大限角接触を増やす位置を選ぶはずだが、
      // テスト環境では(0,0)にすでに1セル配置済みなので、(1,1)は角接触が1箇所増える好位置。
      //
      // 調べ方:
      // candidate.origin が (1,1) を期待する。
      #expect(candidate.origin == Coordinate(x:1, y:0) || candidate.origin == Coordinate(x:0, y:1) || candidate.origin == Coordinate(x:1, y:1),
              "Hardは角接触増加を狙うため、(0,0)に隣接した斜め方向を狙う")
    } else {
      Issue.record("候補があるはずなのにnilが返った")
    }
  }
  
  @Test
  func testHardMultiplePiecesWithDifferentShapes() async throws {
    var board = Board()
    let owner = PlayerColor.red
    
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
