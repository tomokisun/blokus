import SwiftUI

struct GameView: View {
  @State var store: Store
  @Environment(\.cellSize) var cellSize

  var body: some View {
    VStack(spacing: 12) {
      BoardView(board: $store.board) { coordinate in
        store.movePlayerPiece(at: coordinate)
      }
      .overlay {
        if case let .thinking(computer) = store.thinkingState {
          Color.black.opacity(0.7)
            .overlay {
              Label("\(computer.rawValue) is thinking...", systemImage: "progress.indicator")
                .foregroundStyle(Color.white)
                .symbolEffect(.variableColor.iterative)
            }
        }
      }
      
      VStack(spacing: 12) {
        Picker(selection: $store.player) {
          ForEach(PlayerColor.allCases, id: \.color) { playerColor in
            let point = store.board.score(for: playerColor)
            let text = "\(playerColor.rawValue): \(point)pt"
            Text(text)
              .tag(playerColor)
          }
        } label: {
          Text("label")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .disabled(store.computerMode)
        
        HStack(spacing: 40) {
          Button {
            store.rotatePiece()
          } label: {
            Label("Rotate", systemImage: "rotate.right")
          }
          
          Button {
            store.flipPiece()
          } label: {
            Label("Flip", systemImage: "trapezoid.and.line.vertical")
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)
      
      ScrollView(.horizontal) {
        HStack(spacing: 20) {
          ForEach(store.playerPieces) { piece in
            Button {
              store.pieceSelection = piece
              store.updateBoardHighlights()
            } label: {
              PieceView(cellSize: cellSize, piece: piece)
                .padding()
                .background(piece == store.pieceSelection ? store.player.color.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
        }
        .padding(.horizontal, 20)
      }
      .sensoryFeedback(.impact, trigger: store.pieceSelection)
      .sensoryFeedback(.impact, trigger: store.pieces)
      .sensoryFeedback(.impact, trigger: store.player)
    }
  }
}

#Preview {
  GeometryReader { proxy in
    GameView(
      store: Store(
        isHighlight: true,
        computerMode: true,
        computerLevel: ComputerLevel.normal
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}
