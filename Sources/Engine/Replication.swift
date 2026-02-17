import Foundation
import Domain

public extension GameEngine {
  func applyRemoteEvents(_ incoming: [MoveEvent], at now: Date = .init()) -> RemoteIngestResult {
    let result = RemoteEventProcessor.process(
      incoming: incoming,
      state: state,
      existingEvents: events,
      chainHashComputer: computeChainHash,
      now: now
    )
    state = result.finalState
    events.append(contentsOf: result.committedEvents)
    return result
  }
}
