import SwiftUI

struct GameView: View {
  @State var store: Store
  @Environment(\.cellSize) var cellSize
  @State var isPresented = false

  var body: some View {
    VStack(spacing: 12) {
      BoardView(board: $store.board) { coordinate in
        store.cellButtonTapped(at: coordinate)
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
        Picker(
          selection: Binding(
            get: { store.player },
            set: { _ in }
          )
        ) {
          ForEach(Player.allCases, id: \.color) { playerColor in
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
        .allowsHitTesting(false)
        
        HStack(spacing: 40) {
          Button {
            store.rotatePiece()
          } label: {
            let flipped = store.pieceSelection?.orientation.flipped ?? false
            Label("Rotate", systemImage: flipped ? "rotate.right" : "rotate.left")
          }
          .disabled(store.pieceSelection == nil)
          
          Button {
            isPresented = true
          } label: {
            Text("Replay")
          }
          
          Button {
            store.flipPiece()
          } label: {
            Label("Flip", systemImage: "trapezoid.and.line.vertical")
          }
          .disabled(store.pieceSelection == nil)
        }
      }
      
      ScrollView(.vertical) {
        LazyVGrid(
          columns: Array(repeating: GridItem(spacing: 0), count: 3),
          alignment: .center,
          spacing: 0
        ) {
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
        
        Button {
          store.passButtonTapped()
        } label: {
          Text("Pass")
            .frame(height: cellSize * 3)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
      }
      .sensoryFeedback(.impact, trigger: store.pieceSelection)
      .sensoryFeedback(.impact, trigger: store.pieces)
      .sensoryFeedback(.impact, trigger: store.player)
    }
    .sheet(isPresented: $isPresented) {
      ReplayView(store: ReplayStore(turns: store.turnRecorder.turns))
    }
  }
}

#Preview {
  GeometryReader { proxy in
    GameView(
      store: Store(
        isHighlight: true,
        computerMode: true,
        computerLevel: ComputerLevel.hard
      )
    )
    .environment(\.cellSize, proxy.size.width / 20)
  }
}
