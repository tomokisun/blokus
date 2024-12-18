import SwiftUI

struct ContentView: View {
  @Environment(\.cellSize) var cellSize
  let isHighlight: Bool
  let computerMode: Bool
  let computerLevel: ComputerLevel

  @State var board = Board()
  @State var selection: Piece?
  @State var player = PlayerColor.red
  
  @State var pieces: [Piece] = Piece.allPieces
  @State var cpuPlayers: [ComputerPlayer]
  
  init(
    isHighlight: Bool,
    computerMode: Bool,
    computerLevel: ComputerLevel
  ) {
    self.isHighlight = isHighlight
    self.computerMode = computerMode
    self.computerLevel = computerLevel

    self.cpuPlayers = [
      ComputerPlayer(owner: .blue, level: computerLevel),
      ComputerPlayer(owner: .green, level: computerLevel),
      ComputerPlayer(owner: .yellow, level: computerLevel)
    ]
  }
  
  func point(_ player: PlayerColor) -> Int {
    return pieces
      .filter { $0.owner == player }
      .map(\.baseShape.count)
      .reduce(0, +)
  }
  
  var body: some View {
    VStack(spacing: 20) {
      BoardView(board: $board) { coordinate in
        guard let piece = selection else { return }
        do {
          try board.placePiece(piece: piece, at: coordinate)

          withAnimation(.default) {
            pieces.removeAll(where: { $0.id == piece.id })
            selection = nil
          } completion: {
            guard computerMode else { return }
            DispatchQueue.global(qos: .userInitiated).async {
              do {
                if let candidate = cpuPlayers[0].moveCandidate(board: board, pieces: pieces) {
                  try board.placePiece(piece: candidate.piece, at: candidate.origin)
                  DispatchQueue.main.async {
                    if let idx = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
                      pieces.remove(at: idx)
                    }
                  }
                }
                
                if let candidate = cpuPlayers[1].moveCandidate(board: board, pieces: pieces) {
                  try board.placePiece(piece: candidate.piece, at: candidate.origin)
                  DispatchQueue.main.async {
                    if let idx = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
                      pieces.remove(at: idx)
                    }
                  }
                }
                
                if let candidate = cpuPlayers[2].moveCandidate(board: board, pieces: pieces) {
                  try board.placePiece(piece: candidate.piece, at: candidate.origin)
                  DispatchQueue.main.async {
                    if let idx = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
                      pieces.remove(at: idx)
                    }
                  }
                }
              } catch {
                print(error)
              }
            }
          }
        } catch {
          print(error)
        }
      }
      
      VStack(spacing: 20) {
        Picker(selection: $player) {
          ForEach(PlayerColor.allCases, id: \.color) { playerColor in
            let text = "\(playerColor.rawValue): \(point(playerColor))pt"
            Text(text)
              .tag(playerColor)
          }
        } label: {
          Text("label")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .disabled(computerMode)
        
        HStack(spacing: 40) {
          Button {
            withAnimation(.default) {
              self.pieces = pieces.map { piece in
                Piece(id: piece.id, owner: piece.owner, baseShape: piece.baseShape, orientation: Orientation(
                  rotation: piece.orientation.rotation.rotate90(),
                  flipped: piece.orientation.flipped
                ))
              }
            }
          } label: {
            Label("Rotate", systemImage: "rotate.right")
          }
          
          Button {
            withAnimation(.default) {
              self.pieces = pieces.map { piece in
                Piece(id: piece.id, owner: piece.owner, baseShape: piece.baseShape, orientation: Orientation(
                  rotation: piece.orientation.rotation,
                  flipped: !piece.orientation.flipped
                ))
              }
            }
          } label: {
            Label("Flip", systemImage: "trapezoid.and.line.vertical")
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)

      ScrollView(.horizontal) {
        HStack(spacing: 20) {
          ForEach(pieces.filter { $0.owner == player }) { piece in
            Button {
              selection = piece
            } label: {
              PieceView(cellSize: cellSize, piece: piece)
                .padding()
                .background(piece == selection ? player.color.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }
    .sensoryFeedback(.impact, trigger: selection)
    .sensoryFeedback(.impact, trigger: pieces)
    .sensoryFeedback(.impact, trigger: player)
    .onChange(of: selection) {
      if isHighlight {
        if let piece = selection {
          // ピース選択時にハイライト
          board.highlightPossiblePlacements(for: piece)
        } else {
          // ピース未選択時はハイライト解除
          board.clearHighlights()
        }
      }
    }
  }
}

