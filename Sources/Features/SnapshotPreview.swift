#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain
import Engine

public struct SnapshotPreview: View {
  public init() {}
  public var body: some View {
    let engine = GameEngine(
      state: GameState(
        gameId: "PREVIEW",
        players: [.blue, .yellow],
        authorityId: .blue
      )
    )
    VStack(spacing: 12) {
      Text("Blokus")
        .font(.headline)
      Text("Phase: \(engine.state.phase.rawValue)")
      Text("Active: \(engine.state.activePlayerId.displayName)")
      Text("Expected Seq: \(engine.state.expectedSeq)")
      Text("Coord Seq: \(engine.state.coordinationSeq)")
    }
    .padding()
    .background(
      LinearGradient(
        colors: [Color.blue.opacity(0.15), Color.gray.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .cornerRadius(12)
  }
}

#Preview {
  SnapshotPreview()
}
#endif
