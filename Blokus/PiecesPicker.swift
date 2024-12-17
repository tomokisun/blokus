import SwiftUI
import PhotosUI

struct PiecesPicker<Label: View>: View {
  @State var isPresented: Bool = false
  
  @Binding var pieces: [Piece]
  @Binding var selection: Piece?
  var label: () -> Label
  
  init(pieces: Binding<[Piece]>, selection: Binding<Piece?>, label: @escaping () -> Label) {
    self._pieces = pieces
    self._selection = selection
    self.label = label
  }

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      label()
    }
    .sensoryFeedback(.impact, trigger: isPresented)
    .sheet(isPresented: $isPresented) {
      VStack(spacing: 40) {
        ScrollView(.vertical) {
          HStack(spacing: 0) {
            VStack(spacing: 20) {
              ForEach(pieces.filter { $0.owner.color == .red }) { piece in
                Button {
                  selection = piece
                  isPresented = false
                } label: {
                  PieceView(cellSize: 20, piece: piece)
                }
              }
            }
            
            VStack(spacing: 20) {
              ForEach(pieces.filter { $0.owner.color == .blue }) { piece in
                Button {
                  selection = piece
                  isPresented = false
                } label: {
                  PieceView(cellSize: 20, piece: piece)
                }
              }
            }
            
            VStack(spacing: 20) {
              ForEach(pieces.filter { $0.owner.color == .green }) { piece in
                Button {
                  selection = piece
                  isPresented = false
                } label: {
                  PieceView(cellSize: 20, piece: piece)
                }
              }
            }
            
            VStack(spacing: 20) {
              ForEach(pieces.filter { $0.owner.color == .yellow }) { piece in
                Button {
                  selection = piece
                  isPresented = false
                } label: {
                  PieceView(cellSize: 20, piece: piece)
                }
              }
            }
          }
          .padding(.vertical, 40)
        }
        
        HStack(spacing: 40) {
          Button("Rotate") {
            withAnimation(.default) {
              self.pieces = pieces.map { piece in
                Piece(id: piece.id, owner: piece.owner, baseShape: piece.baseShape, orientation: Orientation(
                  rotation: piece.orientation.rotation.rotate90(),
                  flipped: piece.orientation.flipped
                ))
              }
            }
          }
          
          Button("Flip") {
            withAnimation(.default) {
              self.pieces = pieces.map { piece in
                Piece(id: piece.id, owner: piece.owner, baseShape: piece.baseShape, orientation: Orientation(
                  rotation: piece.orientation.rotation,
                  flipped: !piece.orientation.flipped
                ))
              }
            }
          }
        }
      }
    }
  }
}
