import SwiftUI
import ComposableArchitecture
import StoreKit

@main
struct BlokusApp: App {
  @Environment(\.requestReview) var requestReview

  private let store = Store(
    initialState: RootFeature.State(),
    reducer: {
      RootFeature()
    },
    withDependencies: {
      $0.aiEngineClient = RandomAIEngineClient()
      $0.auditLogger = LiveAuditLogger()
    }
  )
  
  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        RootView(store: store)
          .persistentSystemOverlays(.hidden)
          .environment(\.cellSize, proxy.size.width / 20)
          .task {
            requestReview()
          }
      }
    }
  }
}

extension EnvironmentValues {
  @Entry var cellSize = CGFloat.zero
}
