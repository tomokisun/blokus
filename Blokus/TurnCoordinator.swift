import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct TurnCoordinator {
  @ObservableState struct State {
    var inFlight: InFlightState?
    var queueDepth = 0
    var pendingSnapshot: ReadOnlyGameStateSnapshot?
    var pendingResult: MoveDecision?
    var pendingRequestId: UUID?
  }

  struct InFlightState: Equatable {
    let requestId: UUID
  }

  enum Action: Equatable {
    case launchIfNeeded
    case receiveAIResult(TaskResult<MoveDecision>, UUID)
    case cancelInFlight
  }

  enum CancelID { case aiInFlight }

  @Dependency(\.aiEngineClient) var aiEngine
  @Dependency(\.auditLogger) var auditLogger
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .launchIfNeeded:
        guard let snapshot = state.pendingSnapshot else {
          return .none
        }
        guard snapshot.computerMode else {
          return .none
        }
        guard snapshot.player != .red else {
          return .none
        }

        if state.inFlight != nil {
          state.inFlight = nil
          state.pendingResult = nil
          state.pendingRequestId = nil
          state.queueDepth = max(0, state.queueDepth - 1)
        }

        let requestId = uuid()
        state.inFlight = InFlightState(requestId: requestId)
        state.pendingRequestId = requestId
        state.pendingResult = nil
        state.queueDepth += 1

        return .run { [snapshot, requestId] send in
          let result = await TaskResult { try await self.aiEngine.nextMove(snapshot) }
          await send(.receiveAIResult(result, requestId))
        }
        .cancellable(id: CancelID.aiInFlight, cancelInFlight: true)

      case let .receiveAIResult(taskResult, requestId):
        guard let inFlight = state.inFlight else {
          state.pendingSnapshot = nil
          state.pendingRequestId = nil
          logDiscarded(
            reason: "stale_result",
            requestId: requestId,
            inFlightRequestId: nil
          )
          return .none
        }
        guard inFlight.requestId == requestId else {
          logDiscarded(
            reason: "stale_request",
            requestId: requestId,
            inFlightRequestId: inFlight.requestId
          )
          state.inFlight = nil
          state.pendingSnapshot = nil
          state.pendingResult = nil
          state.pendingRequestId = nil
          state.queueDepth = max(0, state.queueDepth - 1)
          return .none
        }

        switch taskResult {
        case .success(let result):
          state.pendingResult = result
        case .failure(let error):
          _ = error
          state.pendingResult = .pass
        }

        state.pendingRequestId = requestId
        state.pendingSnapshot = nil
        state.inFlight = nil
        state.queueDepth = max(0, state.queueDepth - 1)
        auditLogger.log(
          AuditEvent(
            correlationId: requestId.uuidString,
            level: .event,
            name: "ai.received",
            payload: "request=\(requestId)",
            timestamp: Date()
          )
        )
        return .none

      case .cancelInFlight:
        state.pendingSnapshot = nil
        state.inFlight = nil
        state.pendingResult = nil
        state.pendingRequestId = nil
        state.queueDepth = max(0, state.queueDepth - 1)
        return .cancel(id: CancelID.aiInFlight)
      }
    }
  }

  private func logDiscarded(
    reason: String,
    requestId: UUID,
    inFlightRequestId: UUID?
  ) {
    auditLogger.log(
      AuditEvent(
        correlationId: requestId.uuidString,
        level: .debug,
        name: "ai.discarded",
        payload: "\(reason) request=\(requestId) inFlight=\(inFlightRequestId?.uuidString ?? "nil")",
        timestamp: Date()
      )
    )
  }

  func consumeResult(for requestId: UUID, in state: inout State) -> MoveDecision? {
    guard state.pendingRequestId == requestId else { return nil }
    let result = state.pendingResult
    state.pendingRequestId = nil
    state.pendingResult = nil
    return result
  }
}
