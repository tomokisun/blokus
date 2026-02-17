#if canImport(SwiftUI) && (os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS))
import SwiftUI
import Domain
import Persistence

public struct OperationalDashboard: View {
  public let metrics: OperationalMetrics
  public let readOnlyContext: ReadOnlyContext?

  public init(metrics: OperationalMetrics, readOnlyContext: ReadOnlyContext? = nil) {
    self.metrics = metrics
    self.readOnlyContext = readOnlyContext
  }

  private var phaseText: String {
    readOnlyContext?.phase.rawValue ?? "unknown"
  }

  private var gapSummary: String {
    guard let context = readOnlyContext else { return "なし" }
    if context.openGaps.isEmpty { return "なし" }
    let ranges = context.openGaps.map { "\($0.fromSeq)-\($0.toSeq)" }
    return ranges.joined(separator: ", ")
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("運用監視")
        .font(.title)
        .fontWeight(.semibold)

      HStack(spacing: 12) {
        dashboardCard("gap_open_count", value: "\(metrics.gapOpenCount)")
        dashboardCard("queued_count", value: "\(metrics.queuedCount)")
      }

      HStack(spacing: 12) {
        dashboardCard("fork_count", value: "\(metrics.forkCount)")
        dashboardCard("orphan_rate", value: String(format: "%.2f", metrics.orphanRate))
      }

      HStack(spacing: 12) {
        dashboardCard("readOnly phase", value: phaseText)
        dashboardCard("retry_count", value: "\(metrics.latestRetryCount)")
      }

      if let context = readOnlyContext {
        VStack(alignment: .leading, spacing: 6) {
          Text("ReadOnly / 復旧状況")
            .font(.headline)
          Text("gap range: \(gapSummary)")
          Text("latestMatchedSeq: \(context.latestMatchedCoordinationSeq)")
          if let eventId = context.lastSeenOrphanEventId {
            Text("lastOrphanEvent: \(eventId.uuidString)")
          }
          if let reason = context.lastSeenOrphanReason {
            Text("lastOrphanReason: \(reason)")
          }
          if let lastFailure = context.lastFailureAt {
            Text("lastFailureAt: \(lastFailure)")
          }
          Text("retryCount: \(context.retryCount)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding()
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.yellow.opacity(0.15))
        )
      }
    }
    .padding(16)
    .background(
      LinearGradient(
        colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .cornerRadius(16)
  }

  @ViewBuilder
  private func dashboardCard(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
      Text(value)
        .font(.headline)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.75))
    )
  }
}

#Preview {
  let metrics = OperationalMetrics(
    gapOpenCount: 2,
    gapRecoveryDurationMs: 4500,
    queuedCount: 1,
    forkCount: 0,
    orphanRate: 0.12,
    latestRetryCount: 3
  )
  let context = ReadOnlyContext(
    gameId: "GAME-PREVIEW",
    phase: .readOnly,
    openGaps: [
      EventGap(
        fromSeq: 5,
        toSeq: 7,
        detectedAt: Date(),
        retryCount: 3,
        nextRetryAt: Date(),
        lastError: "sequence_gap",
        maxRetries: 5,
        deadlineAt: Date().addingTimeInterval(30)
      )
    ],
    latestMatchedCoordinationSeq: 4,
    lastSeenOrphanEventId: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
    lastSeenOrphanReason: "coordination_conflict",
    retryCount: 3,
    lastFailureAt: Date().addingTimeInterval(-120)
  )
  OperationalDashboard(metrics: metrics, readOnlyContext: context)
}
#endif
