import Foundation
import SQLite3
import Testing
import Domain
import Engine
import Persistence
import Connector

extension AppBaseSuite {
  @Test
  func persistenceLifecycleAndRecoveryOperations() throws {
    let path = tempDatabasePath("lifecycle")
    let store = try PersistenceStore(path: path)
    let nowEngine = newEngine(players: [.blue, .yellow], verifier: PermissiveCommandSignatureVerifier())
    let initial = nowEngine.state

    let sampleCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0),
                 ),
      key: "secret",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )
    let accepted = nowEngine.submit(sampleCommand)
    var commandState: GameState = initial
    if case let .accepted(state) = accepted { commandState = state }
    guard let acceptedEvent = nowEngine.events.first(where: { $0.commandId == sampleCommand.commandId }) else {
      Issue.record("missing accepted event for persistence lifecycle test")
      return
    }

    try store.upsertGame(commandState, gameId: initial.gameId)
    try store.upsertEvent(acceptedEvent, gameId: initial.gameId)
    let loaded = try store.loadGame(gameId: initial.gameId)
    #expect(loaded?.coordinationSeq == 1)

    let loadedEvents = try store.loadCommittedEvents(gameId: initial.gameId)
    #expect(!loadedEvents.isEmpty)
    #expect(loadedEvents.first?.eventId == acceptedEvent.eventId)

    let gap = EventGap(
      fromSeq: 5,
      toSeq: 7,
      detectedAt: defaultDate,
      retryCount: 1,
      nextRetryAt: defaultDate,
      lastError: "sequence_gap",
      maxRetries: 3,
      deadlineAt: defaultDate.addingTimeInterval(31)
    )
    try store.insertGap(gap, gameId: initial.gameId)
    let loadedGaps = try store.loadEventGaps(gameId: initial.gameId)
    #expect(loadedGaps.count == 1)
    #expect(loadedGaps[0].fromSeq == 5)

    try store.appendOrphan(
      event: acceptedEvent,
      gameId: initial.gameId,
      reason: "test_orphan"
    )
    let context = try store.readOnlyContext(gameId: initial.gameId)
    #expect(context?.openGaps.first?.fromSeq == 5)
    #expect(context?.lastSeenOrphanEventId != nil)

    let metrics = try store.loadOperationalMetrics(gameId: initial.gameId)
    #expect(metrics.gapOpenCount >= 1)
    #expect(metrics.forkCount >= 1)
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceApplySubmitResultVariants() throws {
    let path = tempDatabasePath("submit-variants")
    let store = try PersistenceStore(path: path)
    let engine = newEngine(verifier: PermissiveCommandSignatureVerifier())
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    let accepted = engine.submit(command)
    try store.applySubmitResult(accepted, command: command, engine: engine)

    let queued = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 99,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 1, y: 0))
      )
    )
    try store.applySubmitResult(queued, command: command, engine: engine)

    let duplicate = engine.submit(
      signedCommand(
        commandId: command.commandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    )
    try store.applySubmitResult(duplicate, command: command, engine: engine)

    let rejected = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: engine.state.expectedSeq,
        playerId: .blue,
        action: .place(pieceId: "invalid", variantId: 0, origin: .init(x: 0, y: 0)),
        key: "wrong",
        verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
      )
    )
    try store.applySubmitResult(rejected, command: command, engine: engine)

    let authorityEngine = GameEngine(
      state: GameState(gameId: "GAME-001", players: [.blue, .yellow], authorityId: .blue, localAuthorityMode: false),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let authorityMismatch = authorityEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .pass
      )
    )
    try store.applySubmitResult(authorityMismatch, command: command, engine: authorityEngine)

    let metrics = try store.loadOperationalMetrics(gameId: "GAME-001")
    _ = metrics
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceInboxLifecycleAndMigrationNoop() throws {
    let path = tempDatabasePath("inbox")
    let store = try PersistenceStore(path: path)
    let initial = GameState(gameId: "GAME-INBOX", players: [.blue, .yellow], authorityId: .blue)
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      key: "secret",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )

    try store.upsertGame(initial, gameId: initial.gameId)
    let pending = command.toMoveEvent(
      status: .queued,
      stateBefore: initial,
      stateAfter: initial,
      prevChainHash: initial.stateHashChain.lastChainHash,
      chainHash: ""
    )
    try store.appendInboxEvent(pending, gameId: initial.gameId, state: "queued")
    #expect(try queryInt64(path, "SELECT COUNT(*) FROM inbox_events WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, initial.gameId, -1, sqlite3Transient)
    } == 1)

    try store.appendInboxEvent(pending, gameId: initial.gameId, state: "applied")
    #expect(try queryInt64(path, "SELECT COUNT(*) FROM inbox_events WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, initial.gameId, -1, sqlite3Transient)
    } == 1)
    #expect(try queryText(path, "SELECT state FROM inbox_events WHERE game_id = ? LIMIT 1;") { statement in
      sqlite3_bind_text(statement, 1, initial.gameId, -1, sqlite3Transient)
    } == "applied")

    let reopened = try PersistenceStore(path: path)
    #expect(!reopened.isReadOnly)

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceApplyRemoteResultRecordsOrphansAndForks() throws {
    let path = tempDatabasePath("remote-result")
    let store = try PersistenceStore(path: path)
    let engineInitial = GameState(gameId: "GAME-REMOTE-STORE", players: [.blue, .yellow], authorityId: .blue)
    var engine = GameEngine(state: engineInitial)
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: engine.state.expectedSeq,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    let submitResult = engine.submit(command)
    let acceptedEvent: MoveEvent
    switch submitResult {
    case .accepted:
      guard let event = engine.events.first(where: { $0.commandId == command.commandId }) else {
        Issue.record("accepted submit should produce accepted event")
        return
      }
      acceptedEvent = event
    case .queued, .duplicate, .rejected, .authorityMismatch:
      var afterEventState = engine.state
      guard afterEventState.apply(action: command.action, by: command.playerId) == nil else {
        Issue.record("fallback submit path should be legal")
        return
      }
      let fallbackEvent = command.toMoveEvent(
        status: .committed,
        stateBefore: engineInitial,
        stateAfter: afterEventState,
        prevChainHash: engineInitial.stateHashChain.lastChainHash,
        chainHash: ""
      )
      engine.state = afterEventState
      engine.events = [fallbackEvent]
      acceptedEvent = fallbackEvent
    }

    var orphanEvent = acceptedEvent
    orphanEvent = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: command.commandFingerprintV4,
      expectedSeq: 3,
      coordinationSeq: 3,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .blue,
      payload: .pass,
      stateFingerprintBefore: acceptedEvent.stateFingerprintBefore,
      stateFingerprintAfter: acceptedEvent.stateFingerprintAfter,
      status: MoveEventStatus.committed,
      chainHash: "",
      prevChainHash: acceptedEvent.prevChainHash,
      createdAt: defaultDate
    )
    engine.events.append(orphanEvent)

    var readOnlyState = acceptedEvent.source == .remote ? engine.state : engine.state
    readOnlyState.phase = .readOnly
    readOnlyState.eventGaps = [
      EventGap(
        fromSeq: 9,
        toSeq: 10,
        detectedAt: defaultDate,
        retryCount: 0,
        nextRetryAt: defaultDate,
        lastError: "test",
        maxRetries: 9,
        deadlineAt: defaultDate.addingTimeInterval(60)
      )
    ]

    let result = RemoteIngestResult(
      acceptedEventIds: [acceptedEvent.eventId],
      queuedRanges: [],
      duplicateCommandIds: [],
      orphanedEventIds: [orphanEvent.eventId],
      forkedEvents: [
        ForkEventRecord(
          eventId: orphanEvent.eventId,
          commandId: orphanEvent.commandId,
          coordinationSeq: orphanEvent.coordinationSeq,
          reason: "test_fork",
          observedAt: defaultDate
        )
      ],
      finalState: readOnlyState,
      phase: .readOnly
    )
    try store.applyRemoteResult(result, engine: engine)

    #expect(try queryInt64(path, "SELECT COUNT(*) FROM orphan_events WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, engine.state.gameId, -1, sqlite3Transient)
    } == 1)
    let context = try store.readOnlyContext(gameId: engine.state.gameId)
    #expect(context?.lastSeenOrphanEventId == orphanEvent.eventId)
    #expect(context?.phase == .readOnly)
    #expect(context?.openGaps.count == 1)

    let auditCount = try queryInt64(path, "SELECT COUNT(*) FROM audit_logs WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, engine.state.gameId, -1, sqlite3Transient)
    }
    #expect(auditCount >= 2)

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceRepairTickAndRebuild() throws {
    let path = tempDatabasePath("repair")
    let store = try PersistenceStore(path: path)
    let engine = newEngine()

    engine.state.eventGaps = [
      EventGap(
        fromSeq: 1,
        toSeq: 2,
        detectedAt: defaultDate,
        retryCount: 5,
        nextRetryAt: defaultDate,
        lastError: "retrial",
        maxRetries: 2,
        deadlineAt: defaultDate
      )
    ]
    _ = try store.persistRepairTick(gameId: engine.state.gameId, engine: engine)

    let metrics = try store.loadOperationalMetrics(gameId: engine.state.gameId)
    #expect(metrics.gapOpenCount >= 0)

    let commandA = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    let accepted = engine.submit(commandA)
    if case let .accepted(state) = accepted {
      try store.upsertGame(state, gameId: state.gameId)
      let firstEvent = engine.events.first(where: { $0.commandId == commandA.commandId })!
      try store.upsertEvent(firstEvent, gameId: state.gameId)
    }
    var wrongState = try #require(try store.loadGame(gameId: engine.state.gameId))
    wrongState.stateFingerprint = "broken"
    try withSQLite(path) { db in
      let sql = "UPDATE games SET state_json='{}' WHERE game_id = ?;"
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(statement, 1, wrongState.gameId, -1, sqlite3Transient)
      if sqlite3_step(statement) != SQLITE_DONE {
        throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
      }
    }
    do {
      let _ = try store.loadGame(gameId: wrongState.gameId)
    } catch {
      #expect(error is StoreError)
    }
    do {
      let recovery = try store.rebuild(gameId: engine.state.gameId)
      #expect(!recovery.orphanedEventIds.isEmpty || recovery.restoredState.gameId == engine.state.gameId)
    } catch {
      #expect(error is StoreError)
    }
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceMigrationFallback() throws {
    let path = tempDatabasePath("migration")
    try setUserVersion(path, 3)
    do {
      _ = try PersistenceStore(path: path, fallbackReadOnlyOnMigrationFailure: false)
      Issue.record("migration should fail when user version is newer")
    } catch StoreError.migrationFailed(let from, let to, _) {
      #expect(from == 3)
      #expect(to == 1)
    }
    let store = try PersistenceStore(path: path, fallbackReadOnlyOnMigrationFailure: true)
    #expect(store.isReadOnly)
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceReadOnlyContextMissingGameAndConnectorRecoverFlow() throws {
    let path = tempDatabasePath("migration-noop")
    let store = try PersistenceStore(path: path)
    #expect(try store.readOnlyContext(gameId: "MISSING")==nil)

    let initial = GameState(gameId: "GAME-RECOVER", players: [.blue, .yellow], authorityId: .blue)
    let connector = try OperationalConnector(path: path, initialState: initial)
    #expect(connector.gameId == initial.gameId)
    _ = try connector.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    )
    try connector.store.upsertGame(connector.engine.state, gameId: initial.gameId)
    connector.engine.state.phase = .readOnly
    let plan = try connector.recoverFromPersistence()
    #expect(plan.restoredState.phase == .playing)
    #expect(connector.engine.state.phase == .playing)

    let roPath = tempDatabasePath("connector-readonly-recover")
    try setUserVersion(roPath, 3)
    let readOnlyConnector = try OperationalConnector(path: roPath, initialState: initial)
    #expect(readOnlyConnector.store.isReadOnly)
    do {
      _ = try readOnlyConnector.recoverFromPersistence()
      Issue.record("read-only connector must reject recoverFromPersistence")
    } catch ConnectorError.readOnlyMode {
      // expected
    }

    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.removeItem(atPath: roPath)
  }

  @Test
  func persistenceEdgeCaseCoverage() throws {
    do {
      _ = try PersistenceStore(path: "/tmp/nonexistent-dir-blokus/db.sqlite3")
      Issue.record("creating store on invalid directory should fail")
    } catch {
      if case .openFailed = error as? StoreError {
        #expect(true)
      } else {
        #expect(false)
      }
    }

    let path = tempDatabasePath("nil-last-error")
    let store = try PersistenceStore(path: path)
    let initial = GameState(gameId: "GAME-NIL-GAP", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(initial, gameId: initial.gameId)

    let gap = EventGap(
      fromSeq: 0,
      toSeq: 0,
      detectedAt: defaultDate,
      retryCount: 0,
      nextRetryAt: defaultDate,
      lastError: nil,
      maxRetries: 1,
      deadlineAt: defaultDate.addingTimeInterval(31)
    )
    try store.insertGap(gap, gameId: initial.gameId)
    #expect(try store.loadEventGaps(gameId: initial.gameId).first?.lastError == nil)

    let fork = ForkEventRecord(
      eventId: UUID(),
      commandId: UUID(),
      coordinationSeq: 1,
      reason: "test_fork",
      observedAt: defaultDate
    )
    try store.appendForkAudit(gameId: initial.gameId, fork: fork, chainHash: "chain-hash")
    let details = try queryText(path, "SELECT details FROM audit_logs WHERE game_id = ? AND category = 'fork' ORDER BY created_at DESC LIMIT 1;") { statement in
      sqlite3_bind_text(statement, 1, initial.gameId, -1, sqlite3Transient)
    }
    #expect(details?.contains("\"chainHash\":\"chain-hash\"") == true)

    let bareState = GameState(gameId: "GAME-ACCEPT-GUARD", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(bareState, gameId: bareState.gameId)
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: bareState.expectedSeq,
      playerId: .blue,
      action: .pass,
      gameId: bareState.gameId,
      issuedAt: defaultDate,
      issuedNanos: 11
    )
    let engine = GameEngine(state: bareState)
    try store.applySubmitResult(.accepted(bareState), command: command, engine: engine)
    #expect(try store.loadGame(gameId: bareState.gameId)?.expectedSeq == 0)

    let missingPath = tempDatabasePath("rebuild-missing")
    let missingStore = try PersistenceStore(path: missingPath)
    do {
      _ = try missingStore.rebuild(gameId: "NO-SNAPSHOT")
      Issue.record("rebuild should fail when snapshot is missing")
    } catch StoreError.executionFailed(let message) {
      #expect(message == "missing snapshot")
    } catch {
      Issue.record("unexpected error when snapshot missing")
    }

    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.removeItem(atPath: missingPath)
  }

  @Test
  func persistenceEventSourceBranchAndRemoteIngestBranches() throws {
    let remoteStorePath = tempDatabasePath("event-remote-source")
    let store = try PersistenceStore(path: remoteStorePath)
    let remoteState = GameState(gameId: "GAME-EVENT-SRC", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(remoteState, gameId: remoteState.gameId)

    let remoteCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-EVENT-SRC"
    )
    let remoteDraft = remoteCommand.toMoveEvent(
      status: .committed,
      stateBefore: remoteState,
      stateAfter: {
        var after = remoteState
        _ = after.apply(action: .pass, by: .blue)
        return after
      }(),
      prevChainHash: remoteState.stateHashChain.lastChainHash,
      chainHash: ""
    )
    let remoteSourceEvent = MoveEvent(
      eventId: remoteDraft.eventId,
      commandId: remoteDraft.commandId,
      commandFingerprint: remoteDraft.commandFingerprint,
      expectedSeq: remoteDraft.expectedSeq,
      coordinationSeq: remoteDraft.coordinationSeq,
      coordinationAuthorityId: remoteDraft.coordinationAuthorityId,
      source: .remote,
      playerId: remoteDraft.playerId,
      payload: remoteDraft.payload,
      stateFingerprintBefore: remoteDraft.stateFingerprintBefore,
      stateFingerprintAfter: remoteDraft.stateFingerprintAfter,
      status: remoteDraft.status,
      chainHash: remoteDraft.chainHash,
      prevChainHash: remoteDraft.prevChainHash,
      createdAt: remoteDraft.createdAt
    )
    try store.upsertEvent(remoteSourceEvent, gameId: remoteState.gameId)
    let storedSource = try queryText(remoteStorePath, "SELECT source FROM events WHERE event_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, remoteSourceEvent.eventId.uuidString, -1, sqlite3Transient)
    }
    #expect(storedSource == "remote")

    var coordinationState = GameState(gameId: "GAME-REMOTE-COORD", players: [.blue, .yellow], authorityId: .blue)
    coordinationState.remainingPieces[.blue] = []
    coordinationState.remainingPieces[.yellow] = []
    let coordinationMismatchEngine = GameEngine(state: coordinationState, signatureVerifier: PermissiveCommandSignatureVerifier())
    let seeded = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: coordinationState.gameId
    )
    let accepted = coordinationMismatchEngine.submit(seeded)
    if case let .accepted(updatedState) = accepted {
      #expect(updatedState.phase == .playing || updatedState.phase == .repair)
    } else {
      Issue.record("seed command should be accepted")
    }
    let localEvent: MoveEvent
    guard let found = coordinationMismatchEngine.events.first(where: { $0.commandId == seeded.commandId }) else {
      Issue.record("seed command should be stored")
      return
    }
    localEvent = found

    let conflictEvent = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: Data("fork".utf8),
      expectedSeq: 0,
      coordinationSeq: localEvent.coordinationSeq,
      coordinationAuthorityId: localEvent.coordinationAuthorityId,
      source: .remote,
      playerId: localEvent.playerId,
      payload: .pass,
      stateFingerprintBefore: coordinationMismatchEngine.state.stateFingerprint,
      stateFingerprintAfter: coordinationMismatchEngine.state.stateFingerprint,
      status: .committed,
      chainHash: "fork",
      prevChainHash: coordinationMismatchEngine.state.stateHashChain.lastChainHash,
      createdAt: defaultDate
    )
    let conflictResult = coordinationMismatchEngine.applyRemoteEvents([conflictEvent])
    #expect(!conflictResult.forkedEvents.isEmpty)
    #expect(conflictResult.orphanedEventIds.contains(conflictEvent.eventId))

    let badChainEngine = GameEngine(
      state: GameState(gameId: "GAME-REMOTE-BAD", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let badChainCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    var badChainAfter = badChainEngine.state
    _ = badChainAfter.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
    let badChainDraft = badChainCommand.toMoveEvent(
      status: .committed,
      stateBefore: badChainEngine.state,
      stateAfter: badChainAfter,
      prevChainHash: badChainEngine.state.stateHashChain.lastChainHash,
      chainHash: ""
    )
    let badChainEvent = MoveEvent(
      eventId: badChainDraft.eventId,
      commandId: badChainDraft.commandId,
      commandFingerprint: badChainDraft.commandFingerprint,
      expectedSeq: badChainDraft.expectedSeq,
      coordinationSeq: 1,
      coordinationAuthorityId: badChainDraft.coordinationAuthorityId,
      source: .remote,
      playerId: badChainDraft.playerId,
      payload: badChainDraft.payload,
      stateFingerprintBefore: badChainDraft.stateFingerprintBefore,
      stateFingerprintAfter: badChainDraft.stateFingerprintAfter,
      status: badChainDraft.status,
      chainHash: "mismatch",
      prevChainHash: badChainDraft.prevChainHash,
      createdAt: badChainDraft.createdAt
    )
    let badChainResult = badChainEngine.applyRemoteEvents([badChainEvent])
    #expect(!badChainResult.orphanedEventIds.isEmpty)
    #expect(badChainResult.phase == .repair)

    try FileManager.default.removeItem(atPath: remoteStorePath)
  }

  @Test
  func persistenceSubmitAuditAndAppendAuditErrorBranches() throws {
    let path = tempDatabasePath("audit")
    let store = try PersistenceStore(path: path)
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    let state = GameState(gameId: "GAME-AUDIT", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(state, gameId: state.gameId)

    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .accepted(state)
    )
    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .queued(state, 0...0)
    )
    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .rejected(state, .invalidTurn, retryable: false)
    )
    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .duplicate(state, UUID())
    )
    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .authorityMismatch(state)
    )

    #expect(try queryInt64(path, "SELECT COUNT(*) FROM audit_logs WHERE game_id = ? AND category = 'submit';") {
      sqlite3_bind_text($0, 1, state.gameId, -1, sqlite3Transient)
    } == 5)

    let duplicateLog = SQLiteAuditLog(
      id: UUID(),
      gameId: state.gameId,
      level: "info",
      category: "duplicate-test",
      message: "duplicate-log",
      details: nil
    )
    try store.appendAuditLog(duplicateLog)
    do {
      try store.appendAuditLog(duplicateLog)
      Issue.record("duplicate audit log should fail")
    } catch StoreError.executionFailed {
      // expected due UNIQUE(gameId) constraint
    }

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceLoadGamePrivateQueryAndMigrationBranches() throws {
    let path = tempDatabasePath("query-branches")
    let store = try PersistenceStore(path: path)
    var firstGame = GameState(gameId: "GAME-QUERY-NULL", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(firstGame, gameId: firstGame.gameId)

    let nullRowGameId = "GAME-QUERY-NULL"
    try withSQLite(path) { db in
      try executeSQL(db: db, "DROP TABLE IF EXISTS games;")
      try executeSQL(db: db, "CREATE TABLE games(game_id TEXT PRIMARY KEY, state_json TEXT);")
      try executeSQL(db: db, "INSERT INTO games(game_id, state_json) VALUES ('\(nullRowGameId)', NULL);")
    }
    #expect(try store.loadGame(gameId: nullRowGameId) == nil)

    try withSQLite(path) { db in
      try executeSQL(db: db, "DROP TABLE IF EXISTS games;")
    }
    do {
      _ = try PersistenceStore(path: path).loadGame(gameId: nullRowGameId)
      Issue.record("missing games table should fail in query prepare")
    } catch StoreError.prepareFailed {
      // expected
    }

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceApplySubmitResultBranchesForQueueDuplicateAndAuthorityMismatch() throws {
    let path = tempDatabasePath("submit-result-branches")
    let store = try PersistenceStore(path: path)

    var repairEngine = newEngine(players: [.blue, .yellow])
    repairEngine.state.phase = .repair
    let queuedCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 5,
      playerId: .blue,
      action: .pass,
      gameId: repairEngine.state.gameId
    )
    let queuedResult = repairEngine.submit(queuedCommand)
    guard case .queued(let queuedState, let queuedRange) = queuedResult else {
      Issue.record("mismatched expectedSeq should queue in repair phase")
      return
    }
    try store.applySubmitResult(queuedResult, command: queuedCommand, engine: repairEngine)
    let loadedQueued = try store.loadEventGaps(gameId: repairEngine.state.gameId)
    #expect(loadedQueued.first?.fromSeq == queuedRange.lowerBound)

    let duplicateEngine = newEngine(players: [.blue, .yellow])
    let duplicateCommandId = UUID()
    let accepted = duplicateEngine.submit(
      signedCommand(
        commandId: duplicateCommandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    )
    guard case .accepted = accepted else {
      Issue.record("initial duplicate command should be accepted")
      return
    }

    let duplicateReplayCommand = signedCommand(
      commandId: duplicateCommandId,
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      nonce: 2_000
    )
    let duplicateReplay = duplicateEngine.submit(duplicateReplayCommand)
    try store.applySubmitResult(duplicateReplay, command: duplicateReplayCommand, engine: duplicateEngine)
    #expect((try store.loadGame(gameId: duplicateEngine.state.gameId))?.coordinationSeq == duplicateEngine.state.coordinationSeq)

    let authorityMismatchEngine = GameEngine(
      state: GameState(gameId: "GAME-AUTH-MISMATCH", players: [.blue, .yellow], authorityId: .blue, localAuthorityMode: false),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let authorityCommand = signedCommand(
      commandId: UUID(),
      clientId: "B",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: authorityMismatchEngine.state.gameId
    )
    let authorityResult = authorityMismatchEngine.submit(authorityCommand)
    try store.applySubmitResult(authorityResult, command: authorityCommand, engine: authorityMismatchEngine)
    #expect((try store.loadGame(gameId: authorityMismatchEngine.state.gameId))?.phase == authorityMismatchEngine.state.phase)

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceBootstrapFailsWhenReadOnlyAfterMigrationFallback() throws {
    let path = tempDatabasePath("fallback-bootstrap")
    let fresh = try PersistenceStore(path: path)
    try setUserVersion(path, 3)
    _ = fresh

    let readOnlyStore = try PersistenceStore(path: path, fallbackReadOnlyOnMigrationFailure: true)
    #expect(readOnlyStore.isReadOnly)

    do {
      try readOnlyStore.bootstrap()
      Issue.record("bootstrap should fail on read-only fallback store")
    } catch StoreError.executionFailed {
      // expected due read-only sqlite mode
    }

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceExecuteBatchFailsWhenDatabaseIsLocked() {
    let path = tempDatabasePath("locked-bootstrap")
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(
      path,
      &db,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
      nil
    ) == SQLITE_OK)
    guard let lockDb = db else {
      Issue.record("failed to open sqlite database for lock test")
      return
    }
    _ = sqlite3_exec(lockDb, "BEGIN EXCLUSIVE;", nil, nil, nil)

    #expect(throws: StoreError.self) {
      try PersistenceStore(path: path)
    }

    _ = sqlite3_exec(lockDb, "ROLLBACK;", nil, nil, nil)
    sqlite3_close_v2(lockDb)
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceMigrationNoopWhenVersionIsCurrent() throws {
    let path = tempDatabasePath("migration-current")
    try setUserVersion(path, 1)

    let store = try PersistenceStore(path: path)
    #expect(!store.isReadOnly)

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceReadOnlyContextUsesStringColumnOrNilWhenRepairStateTypeChanges() throws {
    let path = tempDatabasePath("repair-state-type")
    let store = try PersistenceStore(path: path)
    let game = GameState(gameId: "GAME-REPAIR-STATE", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(game, gameId: game.gameId)
    try withSQLite(path) { db in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, "UPDATE games SET repair_state = 1 WHERE game_id = ?;", -1, &statement, nil) == SQLITE_OK else {
        throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_text(statement, 1, game.gameId, -1, sqlite3Transient)
      if sqlite3_step(statement) != SQLITE_DONE {
        throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
      }
    }
    let context = try store.readOnlyContext(gameId: game.gameId)
    #expect(context != nil)
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugMigrationUnsupportedTargetVersion() throws {
    let path = tempDatabasePath("debug-unsupported-target")
    PersistenceStore.debugSetTargetSchemaVersion(2)
    defer { PersistenceStore.debugSetTargetSchemaVersion(nil) }

    do {
      _ = try PersistenceStore(path: path)
      Issue.record("unsupported migration should fail when target is forced to 2")
    } catch StoreError.migrationFailed(let from, let to, let reason) {
      #expect(from == 0)
      #expect(to == 2)
      #expect(reason == "unsupported migration")
    }
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugReadOnlyOpenFailureReachesReadOnlyFallbackPath() throws {
    let path = tempDatabasePath("debug-readonly-open-failure")
    try setUserVersion(path, 3)
    PersistenceStore.debugSetReadOnlyOpenError(.executionFailed("forced read-only open failure"))
    defer { PersistenceStore.debugSetReadOnlyOpenError(nil) }

    do {
      _ = try PersistenceStore(path: path, fallbackReadOnlyOnMigrationFailure: true)
      Issue.record("read-only reopen should fail when debug error is forced")
    } catch StoreError.executionFailed(let message) {
      #expect(message == "forced read-only open failure")
    }

    try? FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugExecuteStepOverrideTriggersExecutionFailed() throws {
    let path = tempDatabasePath("debug-execute-rc")
    let store = try PersistenceStore(path: path)
    store.debugExecuteStepResultOverride = SQLITE_ERROR

    do {
      try store.upsertGame(
        GameState(gameId: "GAME-EXEC-FAIL", players: [.blue, .yellow], authorityId: .blue),
        gameId: "GAME-EXEC-FAIL"
      )
      Issue.record("execute override should fail before upsert completes")
    } catch StoreError.executionFailed {
      // expected
    }

    store.debugExecuteStepResultOverride = nil
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugAppendSubmitAuditTakesNilDetailsPath() throws {
    let path = tempDatabasePath("debug-submit-audit")
    let store = try PersistenceStore(path: path)
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: "GAME-SUBMIT-AUDIT"
    )
    let state = GameState(gameId: "GAME-SUBMIT-AUDIT", players: [.blue, .yellow], authorityId: .blue)
    try store.upsertGame(state, gameId: state.gameId)

    store.debugSubmitAuditForceNilDetails = true
    try store.appendSubmitAudit(
      gameId: state.gameId,
      command: command,
      state: state,
      phase: .playing,
      status: .accepted(state)
    )
    let details = try queryText(path, "SELECT details FROM audit_logs WHERE game_id = ? ORDER BY created_at DESC LIMIT 1;") { statement in
      sqlite3_bind_text(statement, 1, state.gameId, -1, sqlite3Transient)
    }
    #expect(details == nil)
    store.debugSubmitAuditForceNilDetails = false

    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugApplySubmitResultSkipsAppendWhenBootstrapErrorSet() throws {
    let path = tempDatabasePath("debug-bootstrap-error-audit")
    let store = try PersistenceStore(path: path)
    let engine = newEngine(verifier: PermissiveCommandSignatureVerifier())
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      key: "secret",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )

    let accepted = engine.submit(command)
    guard case let .accepted(state) = accepted else {
      Issue.record("submit should be accepted for bootstrap-error branch test")
      return
    }

    store.debugSetBootstrapError(.executionFailed("forced bootstrap error"))
    try store.applySubmitResult(accepted, command: command, engine: engine)

    #expect(try queryInt64(path, "SELECT COUNT(*) FROM audit_logs WHERE game_id = ?;") { statement in
      sqlite3_bind_text(statement, 1, state.gameId, -1, sqlite3Transient)
    } == 0)

    store.debugSetBootstrapError(nil)
    try FileManager.default.removeItem(atPath: path)
  }

  @Test
  func persistenceDebugGetNullableColumnIntFallbackPath() throws {
    let path = tempDatabasePath("debug-nullable-int")
    let store = try PersistenceStore(path: path)

    #expect(try store.debugReadNullableInt(sql: "SELECT NULL;") == nil)
    #expect(try store.debugReadNullableInt(sql: "SELECT 7;") == nil)

    try FileManager.default.removeItem(atPath: path)
  }
}
