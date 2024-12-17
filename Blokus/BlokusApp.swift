import SwiftUI

@main
struct BlokusApp: App {
  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        ContentView()
          .persistentSystemOverlays(.hidden)
          .environment(\.cellSize, proxy.size.width / 20)
      }
    }
  }
}

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}

struct ContentView: View {
  @Environment(\.cellSize) var cellSize

  @State var board = Board()
  @State var selection: Piece?
  @State var colorSelection = Color.red
  
  @State var pieces: [Piece]
  
  init() {
    var pieces = [Piece]()
    coordinates.enumerated().forEach { index, shape in
      PlayerColor.allCases.forEach { owner in
        pieces.append(
          Piece(
            id: (1 + index) * owner.rawValue,
            owner: owner,
            baseShape: shape,
            orientation: Orientation(
              rotation: Rotation.none,
              flipped: false
            )
          )
        )
      }
    }
    self.pieces = pieces
  }
  
  var body: some View {
    VStack(spacing: 20) {
      BoardView(board: $board) { coordinate in
        guard let piece = selection else { return }
        do {
          print(piece, coordinate)
          try board.placePiece(piece: piece, at: coordinate)

          withAnimation(.default) {
            pieces.removeAll(where: { $0.id == piece.id })
            selection = nil
          }
        } catch {
          print(error)
        }
      }
      
      VStack(spacing: 20) {
        Picker(selection: $colorSelection) {
          Text("Red").tag(Color.red)
          Text("Blue").tag(Color.blue)
          Text("Yellow").tag(Color.yellow)
          Text("Green").tag(Color.green)
        } label: {
          Text("label")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        
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
          ForEach(pieces.filter { $0.owner.color == colorSelection }) { piece in
            Button {
              selection = piece
            } label: {
              PieceView(cellSize: cellSize * 2, piece: piece)
                .padding()
                .background(piece == selection ? colorSelection.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }
    .sensoryFeedback(.impact, trigger: selection)
    .sensoryFeedback(.impact, trigger: colorSelection)
    .onChange(of: selection) {
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
