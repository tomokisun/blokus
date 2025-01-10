import SwiftUI
import StoreKit

@main
struct BlokusApp: App {
  @Environment(\.requestReview) var requestReview
  
  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        RootView()
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
