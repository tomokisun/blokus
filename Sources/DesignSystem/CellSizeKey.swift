#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI

private struct CellSizeKey: EnvironmentKey {
  static let defaultValue: CGFloat = 20
}

extension EnvironmentValues {
  public var cellSize: CGFloat {
    get { self[CellSizeKey.self] }
    set { self[CellSizeKey.self] = newValue }
  }
}
#endif
