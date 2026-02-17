import Foundation
import Domain

public enum GapManager {
  public static let initialRetryDelaySec: TimeInterval = 1
  public static let maxRetries = 5
  public static let deadlineWindowSec: TimeInterval = 31
  public static let maxBackoffSec: Double = 16.0

  public static func tick(state: inout GameState, now: Date = .init()) {
    guard !state.eventGaps.isEmpty else { return }
    for idx in state.eventGaps.indices {
      if now >= state.eventGaps[idx].nextRetryAt {
        state.eventGaps[idx].retryCount += 1
        if state.eventGaps[idx].retryCount >= state.eventGaps[idx].maxRetries || now >= state.eventGaps[idx].deadlineAt {
          state.beginReadOnly(now)
          return
        }
        let delay = retryDelay(for: state.eventGaps[idx].retryCount)
        state.eventGaps[idx].nextRetryAt = now.addingTimeInterval(delay)
      }
    }
    if state.phase == .readOnly { return }
    state.phase = .repair
  }

  public static func registerGap(from: Int, to: Int, now: Date, state: inout GameState) {
    let nowFrom = max(0, min(from, to))
    let nowTo = max(nowFrom, max(0, max(from, to)))
    let requested = EventGap(
      fromSeq: nowFrom,
      toSeq: nowTo,
      detectedAt: now,
      retryCount: 0,
      nextRetryAt: now.addingTimeInterval(Self.initialRetryDelaySec),
      lastError: "sequence_gap",
      maxRetries: Self.maxRetries,
      deadlineAt: now.addingTimeInterval(Self.deadlineWindowSec)
    )

    if let index = state.eventGaps.firstIndex(where: { existing in
      existing.toSeq + 1 >= requested.fromSeq && requested.toSeq + 1 >= existing.fromSeq
    }) {
      state.eventGaps[index].fromSeq = min(state.eventGaps[index].fromSeq, requested.fromSeq)
      state.eventGaps[index].toSeq = max(state.eventGaps[index].toSeq, requested.toSeq)
      state.eventGaps[index].detectedAt = requested.detectedAt
      state.eventGaps[index].nextRetryAt = requested.nextRetryAt
      return
    }

    state.eventGaps.append(requested)
    state.eventGaps.sort { $0.fromSeq < $1.fromSeq }
    state.beginRepair(now)
  }

  public static func retryDelay(for failureCount: Int) -> TimeInterval {
    let capped = min(failureCount, maxRetries)
    return min(pow(2.0, Double(capped)), maxBackoffSec)
  }
}
