import SwiftUI
import ReplayKit

@MainActor
@Observable
final class ReplayStore: AnyObject {
  let turns: [Turn]
  var board = Board()
  
  var currentIndex = 0
  var isPaused = false
  var speed: Double = 1.0
  
  var isPlaying: Bool {
    currentIndex < turns.count && !isPaused
  }

  var progress: Double {
    guard !turns.isEmpty else { return 0.0 }
    return Double(currentIndex) / Double(turns.count)
  }

  init(turns: [Turn]) {
    self.turns = turns
      .sorted(by: { $0.index < $1.index })
  }
  
  func start() async {
    // 既に最後まで再生している場合はリセット
    if currentIndex >= turns.count {
      currentIndex = 0
      board = Board()
    }

    isPaused = false

    do {
      while currentIndex < turns.count {
        // 一時停止状態の場合は待機
        while isPaused {
          try await Task.sleep(for: .seconds(0.1))
          try Task.checkCancellation()
        }
        
        let turn = turns[currentIndex]
        
        // スピードに応じて待つ(標準1.0倍速で1秒ごとに進む)
        // speed=2.0なら0.5秒、speed=0.5なら2秒
        let interval = 1.0 / speed
        try await Task.sleep(for: .seconds(interval))
        try Task.checkCancellation()
        
        if case let .place(piece, origin) = turn.action {
          try board.placePiece(piece: piece, at: origin)
        }

        currentIndex += 1
      }
    } catch {
      print("Replay interrupted: \(error)")
    }
  }
  
  func pause() {
    isPaused = true
  }
  
  func resume() {
    // 再開
    if currentIndex < turns.count {
      isPaused = false
    }
  }

  func stop() {
    // 一旦停止
    isPaused = true
    // 最初に戻す
    currentIndex = 0
    board = Board()
  }
}

struct ReplayView: View {
  @State var store: ReplayStore
  @State var task: Task<Void, Never>? = nil
  
  var body: some View {
    VStack(spacing: 20) {
      LazyVGrid(columns: Array(repeating: GridItem(spacing: 0), count: 2), spacing: 0) {
        ForEach(Player.allCases, id: \.color) { playerColor in
          let point = store.board.score(for: playerColor)
          Text("\(point)pt")
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(playerColor.color)
            .foregroundStyle(Color.white)
            .font(.system(.headline, design: .rounded, weight: .bold))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal)

      BoardView(board: $store.board) { _ in }
      
      // 再生進捗バー
      ProgressView(value: store.progress, total: 1.0)
        .padding(.horizontal)
      
      HStack {
        Button(store.isPlaying ? "Pause" : "Play") {
          if store.isPlaying {
            store.pause()
          } else {
            // 再生を開始するタスクを起動
            if store.currentIndex >= store.turns.count {
              // 最初から再生
              store.currentIndex = 0
              store.board = Board()
            }
            store.resume()
            if task?.isCancelled != false {
              task = Task {
                await store.start()
              }
            }
          }
        }

        Button("Stop") {
          store.stop()
          task?.cancel()
          task = nil
        }
      }

      Picker("Speed: \(String(format:"%.1fx", store.speed))", selection: $store.speed) {
        Text("0.5x").tag(0.5)
        Text("1.0x").tag(1.0)
        Text("1.5x").tag(1.5)
        Text("2.0x").tag(2.0)
        Text("3.0x").tag(3.0)
        Text("5.0x").tag(5.0)
      }
    }
    .onDisappear {
      task?.cancel()
    }
  }
}
