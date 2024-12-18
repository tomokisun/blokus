import SwiftUI
import ReplayKit

@MainActor
@Observable
final class ReplayStore: AnyObject {
  let truns: [Trun]
  var board = Board()
  
  init(truns: [Trun]) {
    self.truns = truns
      .sorted(by: { $0.index < $1.index })
  }
  
  func start() async {
    do {
      for trun in truns {
        try await Task.sleep(for: .seconds(1))

        if case let .place(piece, origin) = trun.action {
          try board.placePiece(piece: piece, at: origin)
        }
      }
    } catch {
      print(error)
    }
  }
}

struct ReplayView: View {
  @State var store: ReplayStore

  var body: some View {
    BoardView(board: $store.board) { _ in }
      .task {
        await store.start()
      }
  }
}
