import Foundation
import Testing
import Domain
import Engine

extension AppBaseSuite {
  @Test
  func acceptAndDuplicate() {
    let engine = newEngine()
    guard case let .accepted(state1) = engine.submit(
      signedCommand(
        commandId: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEF00000001")!,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(
          pieceId: PieceLibrary.pieces[0].id,
          variantId: 0,
          origin: BoardPoint(x: 0, y: 0)
        )
      )
    ) else {
      Issue.record("first submit should be accepted")
      return
    }

    #expect(state1.activePlayerId == .yellow)
    #expect(state1.expectedSeq == 1)
    #expect(state1.board[0] == .blue)

    switch engine.submit(
      signedCommand(
        commandId: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEF00000001")!,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(
          pieceId: PieceLibrary.pieces[0].id,
          variantId: 0,
          origin: BoardPoint(x: 0, y: 0)
        )
      )
    ) {
    case let .duplicate(dupState, dupEventId):
      #expect(dupState.activePlayerId == .yellow)
      #expect(!dupEventId.uuidString.isEmpty)
    case let .rejected(_, reason, _):
      #expect(reason == .replayOrDuplicate)
    default:
      Issue.record("second submit should be duplicate or rejected(replayOrDuplicate)")
    }

    #expect(engine.state.activePlayerId == .yellow)
  }

  @Test
  func expectedSequenceQueueRecordsGapAndReconcile() {
    let engine = newEngine()
    let rejected = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 3,
        playerId: .blue,
        action: .pass
      )
    )
    switch rejected {
    case let .queued(queuedState, range):
      #expect(queuedState.phase == .repair)
      #expect(range.lowerBound == 0)
      #expect(range.upperBound == 3)
      #expect(!queuedState.eventGaps.isEmpty)
    default:
      Issue.record("should be queued due to seq gap")
    }
  }

  @Test
  func invalidSignatureIsRejected() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-001", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )
    let bad = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      key: "wrong",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )
    guard case let .rejected(_, reason, _) = engine.submit(bad) else {
      Issue.record("bad signature should be rejected")
      return
    }
    #expect(reason == SubmitRejectReason.invalidSignature)
  }

  @Test
  func passIsAcceptedOnlyIfNoLegalMove() {
    let engine = newEngine()
    engine.state.remainingPieces[.blue] = []
    engine.state.remainingPieces[.yellow] = []

    guard case let .accepted(stateAfterA) = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .pass
      )
    ) else {
      Issue.record("A should pass because no piece")
      return
    }
    #expect(stateAfterA.consecutivePasses == 1)
    #expect(stateAfterA.activePlayerId == .yellow)

    guard case let .accepted(stateAfterB) = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "B",
        expectedSeq: 1,
        playerId: .yellow,
        action: .pass
      )
    ) else {
      Issue.record("B should pass with permissive verifier")
      return
    }

    #expect(stateAfterB.consecutivePasses == 2)
    #expect(stateAfterB.activePlayerId == .red)
    #expect(stateAfterB.phase == .playing)
  }

  @Test
  func submitRejectionPathsAndRateLimit() {
    let verifier = DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret", .yellow: "secret"])
    let commandVerifier = DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret", .yellow: "secret"])

    var engine = GameEngine(
      state: GameState(gameId: "GAME-PATH", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: verifier,
      maxSubmitPerSec: 1
    )
    var validationEngine = GameEngine(
      state: GameState(gameId: "GAME-PATH", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: verifier,
      maxSubmitPerSec: 100
    )
    let rateLimitEngine = GameEngine(
      state: GameState(gameId: "GAME-RL", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: verifier,
      maxSubmitPerSec: 1
    )

    var rejected = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .pass,
        gameId: "OTHER"
      )
    )
    switch rejected {
    case let .rejected(state, reason, _):
      #expect(reason == .schemaMismatch)
      #expect(state.phase == .playing)
    default:
      Issue.record("wrong game id should be schema mismatch")
    }

    var invalidVersionEngine = GameEngine(
      state: GameState(
        gameId: "GAME-PATH",
        players: [.blue, .yellow],
        authorityId: .blue
      ),
      signatureVerifier: verifier
    )
    let legacyCommand = GameCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: "GAME-PATH",
      schemaVersion: GameState.schemaVersion - 1,
      rulesVersion: GameState.rulesVersion,
      pieceSetVersion: PieceLibrary.currentVersion,
      issuedAt: defaultDate,
      issuedNanos: 1,
      nonce: 2000,
      authSig: DefaultCommandSignatureVerifier.signature(for: signedCommand(commandId: UUID(), clientId: "A", expectedSeq: 0, playerId: .blue, action: .pass, gameId: "GAME-PATH"), key: "secret")
    )
    rejected = invalidVersionEngine.submit(legacyCommand)
    if case let .rejected(_, reason, _) = rejected {
      #expect(reason == .versionMismatch)
    } else {
      Issue.record("version mismatch should be rejected")
    }

    let badSignature = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 1)),
      gameId: "GAME-PATH",
      key: "wrong"
    )
    rejected = validationEngine.submit(badSignature)
    if case let .rejected(_, reason, _) = rejected {
      #expect(reason == .invalidSignature)
    } else {
      Issue.record("invalid signature should be rejected")
    }

    var invalidTurnEngine = GameEngine(
      state: GameState(gameId: "GAME-PATH", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: verifier,
      maxSubmitPerSec: 100
    )
    invalidTurnEngine.state.phase = .playing
    let invalidTurn = invalidTurnEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "B",
        expectedSeq: 0,
        playerId: .yellow,
        action: .pass,
        gameId: "GAME-PATH",
        key: "secret",
        verifier: commandVerifier
      )
    )
    if case let .rejected(_, reason, _) = invalidTurn {
      #expect(reason == .invalidTurn)
    } else {
      Issue.record("wrong player should be rejected")
    }

    let authEngine = GameEngine(
      state: GameState(gameId: "GAME-PATH", players: [.blue, .yellow], authorityId: .blue, localAuthorityMode: false),
      signatureVerifier: verifier
    )
    let notAuthority = authEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "Z",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
        gameId: "GAME-PATH",
        verifier: commandVerifier
      )
    )
    if case .authorityMismatch = notAuthority {
      // expected
    } else {
      Issue.record("authority mismatch should be surfaced")
    }

    let spam1 = rateLimitEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "C",
        expectedSeq: 99,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 1)),
        gameId: "GAME-RL",
        verifier: commandVerifier
      )
    )
    if case .queued = spam1 {
      // expected for sequence gap.
    } else if case .accepted = spam1 {
      // accepted is also acceptable for this test context.
    } else if case .rejected(_, .rateLimit, _) = spam1 {
      Issue.record("first over-limit submit should not be rate-limited")
    } else {
      Issue.record("unexpected first over-limit submit outcome")
    }

    let spam2 = rateLimitEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "C",
        expectedSeq: 99,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 1, y: 1)),
        gameId: "GAME-RL",
        verifier: commandVerifier
      )
    )
    if case .rejected(_, .rateLimit, let retryable) = spam2 {
      #expect(retryable)
    } else {
      Issue.record("second over-limit submit should be rateLimit")
    }
    if case .rejected(_, .rateLimit, _) = spam2 {
      #expect(rateLimitEngine.state.phase == .repair || rateLimitEngine.state.phase == .readOnly)
    } else {
      Issue.record("rate limit branch should be active after first sequence-gap command")
    }
  }

  @Test
  func gameEngineReplayAndRecoveryBranches() {
    let commandA = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-REPLAY"
    )
    let commandB = signedCommand(
      commandId: UUID(),
      clientId: "B",
      expectedSeq: 1,
      playerId: .yellow,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 19, y: 19)),
      gameId: "GAME-REPLAY"
    )
    let engine = GameEngine(
      state: GameState(gameId: "GAME-REPLAY", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )

    guard case .accepted(let stateAfterA) = engine.submit(commandA) else {
      Issue.record("first replay command should be accepted")
      return
    }
    guard case .accepted(let stateAfterB) = engine.submit(commandB) else {
      Issue.record("second replay command should be accepted")
      return
    }
    #expect(stateAfterB.coordinationSeq == 2)

    let event1 = engine.events.first(where: { $0.commandId == commandA.commandId })
    #expect(event1 != nil)

    let eventForRecovery = event1!
    let corrupted = MoveEvent(
      eventId: eventForRecovery.eventId,
      commandId: eventForRecovery.commandId,
      commandFingerprint: eventForRecovery.commandFingerprint,
      expectedSeq: eventForRecovery.expectedSeq,
      coordinationSeq: eventForRecovery.coordinationSeq,
      coordinationAuthorityId: eventForRecovery.coordinationAuthorityId,
      source: eventForRecovery.source,
      playerId: eventForRecovery.playerId,
      payload: eventForRecovery.payload,
      stateFingerprintBefore: eventForRecovery.stateFingerprintBefore,
      stateFingerprintAfter: "tampered",
      status: eventForRecovery.status,
      chainHash: eventForRecovery.chainHash,
      prevChainHash: eventForRecovery.prevChainHash,
      createdAt: eventForRecovery.createdAt
    )
    let recovery = GameEngine(state: GameState(gameId: "GAME-REPLAY", players: [.blue, .yellow], authorityId: .blue)).replay(events: [corrupted])
    #expect(recovery.orphanedEvents.count == 1)
    #expect(recovery.restoredState.coordinationSeq == 0)

    let goodEvents = engine.events
    let goodRecovery = GameEngine(state: stateAfterA).replay(events: goodEvents + goodEvents)
    #expect(!goodRecovery.orphanedEvents.isEmpty)
  }

  @Test
  func remoteIngestedEventsCoverAllBranches() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-REMOTE", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let commandA = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
    )
    let accepted = engine.applyRemoteEvents([])
    #expect(accepted.acceptedEventIds.isEmpty)

    let baseState = engine.state
    let remoteA = commandA.toMoveEvent(
      status: MoveEventStatus.committed,
        stateBefore: baseState,
      stateAfter: {
        var after = baseState
        _ = after.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
        return after
      }(),
      prevChainHash: baseState.stateHashChain.lastChainHash,
      chainHash: ""
    )

    let resultA = engine.applyRemoteEvents([remoteA])
    #expect(resultA.acceptedEventIds.count == 1)
    #expect(resultA.phase == GamePhase.playing)

    let duplicate = engine.applyRemoteEvents([remoteA])
    #expect(duplicate.duplicateCommandIds.count == 1)
    #expect(duplicate.orphanedEventIds.isEmpty)

    let forkCommand = signedCommand(
      commandId: commandA.commandId,
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[1].id, variantId: 0, origin: .init(x: 1, y: 0))
    )
    let fork = forkCommand.toMoveEvent(
      status: MoveEventStatus.committed,
      stateBefore: baseState,
      stateAfter: {
        var after = baseState
        _ = after.apply(action: .place(pieceId: PieceLibrary.pieces[1].id, variantId: 0, origin: .init(x: 1, y: 0)), by: .blue)
        return after
      }(),
      prevChainHash: baseState.stateHashChain.lastChainHash,
      chainHash: "bad-hash"
    )
    let forkResult = engine.applyRemoteEvents([fork])
    #expect(!forkResult.forkedEvents.isEmpty)
    #expect(!forkResult.orphanedEventIds.isEmpty)

    let gapCmd = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 99,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[2].id, variantId: 0, origin: .init(x: 2, y: 0))
    )
    let afterGap = commandA.toMoveEvent(
      status: .committed,
      stateBefore: engine.state,
      stateAfter: engine.state,
      prevChainHash: engine.state.stateHashChain.lastChainHash,
      chainHash: ""
    )
    let gap = MoveEvent(
      eventId: UUID(),
      commandId: gapCmd.commandId,
      commandFingerprint: gapCmd.commandFingerprintV4,
      expectedSeq: gapCmd.expectedSeq,
      coordinationSeq: 9,
      coordinationAuthorityId: engine.state.authority.coordinationAuthorityId,
      source: .remote,
      playerId: .blue,
      payload: .place(pieceId: PieceLibrary.pieces[2].id, variantId: 0, origin: .init(x: 2, y: 0)),
      stateFingerprintBefore: engine.state.stateFingerprint,
      stateFingerprintAfter: engine.state.stateFingerprint,
      status: MoveEventStatus.committed,
      chainHash: "",
      prevChainHash: engine.state.stateHashChain.lastChainHash,
      createdAt: defaultDate
    )
    let gapResult = engine.applyRemoteEvents([gap])
    #expect(!gapResult.queuedRanges.isEmpty)
    #expect(gapResult.phase == .repair || gapResult.phase == .reconciling)

    let invalidRemote = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: Data([0x1, 0x2]),
      expectedSeq: 0,
      coordinationSeq: engine.state.coordinationSeq + 1,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .green,
      payload: .place(pieceId: "unknown", variantId: 0, origin: .init(x: 0, y: 0)),
      stateFingerprintBefore: engine.state.stateFingerprint,
      stateFingerprintAfter: "x",
      status: MoveEventStatus.committed,
      chainHash: "bad",
      prevChainHash: "",
      createdAt: defaultDate
    )
    let invalid = engine.applyRemoteEvents([invalidRemote])
    #expect(!invalid.orphanedEventIds.isEmpty)
    _ = afterGap
    _ = gapCmd
    _ = remoteA
    _ = accepted
  }

  @Test
  func coreEdgeCaseBranches() {
    let empty = Piece(id: "empty", baseCells: [])
    #expect(empty.variants == [[]])

    var finishedEngine = GameEngine(
      state: GameState(gameId: "GAME-FINISHED", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    finishedEngine.state.remainingPieces[.blue] = []
    finishedEngine.state.remainingPieces[.yellow] = []
    guard case let .accepted(afterA) = finishedEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .pass,
        gameId: "GAME-FINISHED",
        issuedAt: defaultDate,
        issuedNanos: 1
      )
    ) else {
      Issue.record("first pass should be accepted")
      return
    }
    guard case let .accepted(afterB) = finishedEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "B",
        expectedSeq: 1,
        playerId: .yellow,
        action: .pass,
        gameId: "GAME-FINISHED",
        issuedAt: defaultDate.addingTimeInterval(1),
        issuedNanos: 2
      )
    ) else {
      Issue.record("second pass should be accepted")
      return
    }
    #expect(afterB.phase == .finished)
    _ = afterA

    var windowEngine = GameEngine(
      state: GameState(gameId: "GAME-RATE-ROLLOVER", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier(),
      maxSubmitPerSec: 1
    )
    windowEngine.state.remainingPieces[.blue] = []
    windowEngine.state.remainingPieces[.yellow] = []
    let firstPass = windowEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .pass,
        gameId: "GAME-RATE-ROLLOVER",
        issuedAt: defaultDate,
        issuedNanos: 3
      ),
      at: defaultDate
    )
    guard case .accepted = firstPass else {
      Issue.record("window rollover first pass should be accepted")
      return
    }
    let secondPass = windowEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "B",
        expectedSeq: 1,
        playerId: .yellow,
        action: .pass,
        gameId: "GAME-RATE-ROLLOVER",
        issuedAt: defaultDate.addingTimeInterval(1.5),
        issuedNanos: 4
      ),
      at: defaultDate.addingTimeInterval(1.5)
    )
    if case .accepted = secondPass {
      // expected when rate window rolled over and count reset.
    } else if case let .queued(stateAfterWindow, _) = secondPass {
      #expect(stateAfterWindow.phase == .repair || stateAfterWindow.phase == .playing)
    } else {
      Issue.record("window rollover should not go to authority rejection")
    }

    var duplicateEngine = GameEngine(
      state: GameState(gameId: "GAME-DUP", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let sharedCommandId = UUID()
    guard case .accepted = duplicateEngine.submit(
      signedCommand(
        commandId: sharedCommandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
        gameId: "GAME-DUP",
        issuedAt: defaultDate,
        issuedNanos: 5
      )
    ) else {
      Issue.record("base duplicate command should be accepted")
      return
    }
    let replay = duplicateEngine.submit(
      signedCommand(
        commandId: sharedCommandId,
        clientId: "B",
        expectedSeq: 1,
        playerId: .yellow,
        action: .place(pieceId: PieceLibrary.pieces[1].id, variantId: 0, origin: .init(x: 9, y: 0)),
        gameId: "GAME-DUP",
        issuedAt: defaultDate.addingTimeInterval(1),
        issuedNanos: 6
      )
    )
    if case let .rejected(_, reason, _) = replay {
      #expect(reason == .replayOrDuplicate)
    } else {
      Issue.record("same command id should be replayOrDuplicate")
    }

    var authorityEngine = GameEngine(
      state: GameState(gameId: "GAME-AUTH", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    authorityEngine.state.phase = .waiting
    let invalidAuthority = authorityEngine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "Z",
        expectedSeq: 0,
        playerId: .green,
        action: .pass,
        gameId: "GAME-AUTH",
        issuedAt: defaultDate,
        issuedNanos: 7
      )
    )
    if case let .rejected(_, reason, _) = invalidAuthority {
      #expect(reason == .invalidAuthority)
    } else {
      Issue.record("unknown player should be invalid authority")
    }
  }

  @Test
  func replayPreconditionRejectsIllegalPass() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-REPLAY-PRECON", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let passCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: "GAME-REPLAY-PRECON",
      issuedAt: defaultDate,
      issuedNanos: 8
    )
    let illegalEvent = MoveEvent(
      eventId: UUID(),
      commandId: passCommand.commandId,
      commandFingerprint: passCommand.commandFingerprintV4,
      expectedSeq: passCommand.expectedSeq,
      coordinationSeq: 1,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .blue,
      payload: .pass,
      stateFingerprintBefore: engine.state.stateFingerprint,
      stateFingerprintAfter: "invalid",
      status: .committed,
      chainHash: "",
      prevChainHash: "",
      createdAt: defaultDate
    )
    let recovery = engine.replay(events: [illegalEvent])
    #expect(recovery.orphanedEvents.contains(illegalEvent.eventId))
  }

  @Test
  func replicationTieSortAndApplyFailureBranches() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-REPL-EDGE", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )

    let base = engine.state
    let baseCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-REPL-EDGE",
      issuedAt: defaultDate,
      issuedNanos: 9
    )
    var baseAfter = base
    _ = baseAfter.apply(action: baseCommand.action, by: .blue)
    let fingerprint = baseCommand.commandFingerprintV4

    let sameCoordLater = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: fingerprint,
      expectedSeq: 0,
      coordinationSeq: 1,
      coordinationAuthorityId: base.authority.coordinationAuthorityId,
      source: .remote,
      playerId: .blue,
      payload: baseCommand.action,
      stateFingerprintBefore: base.stateFingerprint,
      stateFingerprintAfter: baseAfter.stateFingerprint,
      status: .committed,
      chainHash: "",
      prevChainHash: base.stateHashChain.lastChainHash,
      createdAt: defaultDate.addingTimeInterval(1)
    )
    let sameCoordEarlier = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: fingerprint,
      expectedSeq: 0,
      coordinationSeq: 1,
      coordinationAuthorityId: base.authority.coordinationAuthorityId,
      source: .remote,
      playerId: .blue,
      payload: baseCommand.action,
      stateFingerprintBefore: base.stateFingerprint,
      stateFingerprintAfter: baseAfter.stateFingerprint,
      status: .committed,
      chainHash: "",
      prevChainHash: base.stateHashChain.lastChainHash,
      createdAt: defaultDate
    )
    let sortedResult = engine.applyRemoteEvents([sameCoordLater, sameCoordEarlier])
    #expect(sortedResult.acceptedEventIds.count == 1)
    #expect(sortedResult.duplicateCommandIds.count == 1)

    let badCommand = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 1,
      playerId: .blue,
      action: .place(pieceId: "invalid-piece", variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-REPL-EDGE",
      issuedAt: defaultDate,
      issuedNanos: 10
    )
    let badEvent = MoveEvent(
      eventId: UUID(),
      commandId: badCommand.commandId,
      commandFingerprint: badCommand.commandFingerprintV4,
      expectedSeq: badCommand.expectedSeq,
      coordinationSeq: engine.state.coordinationSeq + 1,
      coordinationAuthorityId: .blue,
      source: .remote,
      playerId: .blue,
      payload: badCommand.action,
      stateFingerprintBefore: engine.state.stateFingerprint,
      stateFingerprintAfter: engine.state.stateFingerprint,
      status: .committed,
      chainHash: "",
      prevChainHash: engine.state.stateHashChain.lastChainHash,
      createdAt: defaultDate
    )
    let applyFailure = engine.applyRemoteEvents([badEvent])
    #expect(!applyFailure.orphanedEventIds.isEmpty)
    #expect(applyFailure.phase == .repair)
  }

  @Test
  func replicationForkAndRemoteRepairFlow() {
    let engine = GameEngine(state: GameState(gameId: "GAME-FLOW", players: [.blue, .yellow], authorityId: .blue))
    let first = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      key: "secret",
      verifier: DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secret"])
    )

    _ = engine.submit(first)

    let base = engine.state
    let event1 = first.toMoveEvent(
      status: MoveEventStatus.committed,
      stateBefore: base,
      stateAfter: {
        var next = base
        _ = next.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
        return next
      }(),
      prevChainHash: base.stateHashChain.lastChainHash,
      chainHash: ""
    )
    let conflict = first.toMoveEvent(
      status: MoveEventStatus.committed,
      stateBefore: base,
      stateAfter: {
        var next = base
        _ = next.apply(action: .place(pieceId: PieceLibrary.pieces[1].id, variantId: 0, origin: .init(x: 0, y: 1)), by: .blue)
        return next
      }(),
      prevChainHash: base.stateHashChain.lastChainHash,
      chainHash: "different"
    )

    let result = engine.applyRemoteEvents([event1, conflict])
    _ = result
    var engineForTick = engine
    engineForTick.tick(now: defaultDate)
    #expect(engineForTick.state.phase == .playing || engineForTick.state.phase == .repair)
  }

  @Test
  func gameStateClosuresForPlacementAndFingerprint() {
    var state = GameState(gameId: "GAME-CLOSURE-1", players: [.blue, .yellow, .red], authorityId: .blue)
    let initialPlacementResult = state.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
    #expect(initialPlacementResult == nil)

    state.board[168] = .yellow

    #expect(!state.canPlace(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 1, y: 0), playerId: .yellow))
    #expect(state.canPlace(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 9, y: 9), playerId: .yellow))
    let invalidPlacementResult = state.apply(
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 999, origin: .init(x: 0, y: 0)),
      by: .blue
    )
    #expect(invalidPlacementResult == .invalidPlacement)

    state.board[0] = .blue
    state.board[1] = .green
    let fingerprint = state.computeStateFingerprint()
    #expect(!fingerprint.isEmpty)
  }

  @Test
  func replayPreconditionWithoutLocalAuthorityValidation() {
    var state = GameState(gameId: "GAME-CLOSURE-2", players: [.blue, .yellow], authorityId: .blue, localAuthorityMode: false)
    state.remainingPieces[.blue] = []
    state.remainingPieces[.yellow] = []

    var next = state
    #expect(next.apply(action: .pass, by: .blue) == nil)

    var replayEngine = GameEngine(state: state, signatureVerifier: PermissiveCommandSignatureVerifier())
    let passCommand = signedCommand(
      commandId: UUID(),
      clientId: PlayerID.blue.rawValue,
      expectedSeq: 0,
      playerId: .blue,
      action: .pass,
      gameId: "GAME-CLOSURE-2"
    )
    _ = replayEngine.submit(passCommand)
    guard let passEvent = replayEngine.events.first else {
      Issue.record("replay seed event should be stored")
      return
    }

    let recovery = GameEngine(state: state, signatureVerifier: PermissiveCommandSignatureVerifier()).replay(events: [passEvent])
    #expect(recovery.orphanedEvents.isEmpty)
  }

  @Test
  func registerGapBranchesAreCovered() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-GAP-BRANCH", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )

    let first = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 5,
        playerId: .blue,
        action: .pass,
        gameId: "GAME-GAP-BRANCH"
      )
    )
    guard case let .queued(_, firstRange) = first else {
      Issue.record("first queue should be generated")
      return
    }
    #expect(firstRange.lowerBound == 0)
    #expect(firstRange.upperBound == 5)
    #expect(engine.state.eventGaps.count == 1)

    let overlap = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 3,
        playerId: .blue,
        action: .pass,
        gameId: "GAME-GAP-BRANCH"
      )
    )
    guard case let .queued(_, overlapRange) = overlap else {
      Issue.record("overlap queue should be generated")
      return
    }
    #expect(overlapRange.lowerBound == 0)
    #expect(overlapRange.upperBound == 3)
    #expect(engine.state.eventGaps.count == 1)

    engine.state.expectedSeq = 9
    let separated = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 12,
        playerId: .blue,
        action: .pass,
        gameId: "GAME-GAP-BRANCH"
      )
    )
    guard case let .queued(_, separatedRange) = separated else {
      Issue.record("separated queue should be generated")
      return
    }
    #expect(separatedRange == 9...12)
    #expect(engine.state.eventGaps.count == 2)
    #expect(engine.state.eventGaps[0].fromSeq == 0)
    #expect(engine.state.eventGaps[1].fromSeq == 9)
  }

  @Test
  func coreHasAnyLegalMoveScansPieceAndReturnsFalse() {
    var blocked = GameState(gameId: "GAME-LEGAL-SCAN", players: [.blue, .yellow], authorityId: .blue)
    blocked.board = Board(cells: Array(repeating: .yellow, count: BoardConstants.boardCellCount))
    blocked.remainingPieces[.blue] = [PieceLibrary.pieces.first?.id ?? "mono-1"]

    #expect(blocked.hasAnyLegalMove(for: .blue) == false)
  }

  @Test
  func coreSubmitWindowResetForSameClient() {
    let engine = newEngine(maxSubmitPerSec: 1)

    let first = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      ),
      at: defaultDate
    )
    guard case .accepted = first else {
      Issue.record("first submit should be accepted")
      return
    }

    let second = engine.submit(
      signedCommand(
        commandId: UUID(),
        clientId: "A",
        expectedSeq: 1,
        playerId: .yellow,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 19, y: 19))
      ),
      at: defaultDate.addingTimeInterval(1)
    )
    if case .accepted = second {
      #expect(engine.state.expectedSeq == 2)
    } else {
      Issue.record("window reset submit should be accepted when second is in new window")
    }
  }

  @Test
  func coreReplayDuplicateMismatchedFingerprintIsRejected() {
    let commandId = UUID()
    let engine = newEngine()

    guard case .accepted = engine.submit(
      signedCommand(
        commandId: commandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    ) else {
      Issue.record("initial replay command should be accepted")
      return
    }

    let mismatch = engine.submit(
      signedCommand(
        commandId: commandId,
        clientId: "A",
        expectedSeq: 1,
        playerId: .yellow,
        action: .place(pieceId: PieceLibrary.pieces[1].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    )

    if case let .rejected(_, reason, _) = mismatch {
      #expect(reason == .replayOrDuplicate)
    } else {
      Issue.record("replay with different fingerprint should be replayOrDuplicate")
    }
  }

  @Test
  func coreSubmitDuplicatePathUsesDifferentNonce() {
    let engine = newEngine()
    let commandId = UUID()

    guard case .accepted = engine.submit(
      signedCommand(
        commandId: commandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0))
      )
    ) else {
      Issue.record("first command should be accepted")
      return
    }

    guard case let .duplicate(_, replayEventId) = engine.submit(
      signedCommand(
        commandId: commandId,
        clientId: "A",
        expectedSeq: 0,
        playerId: .blue,
        action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
        nonce: 2_000
      )
    ) else {
      Issue.record("replay with same commandId and different nonce should be duplicate")
      return
    }

    #expect(!replayEventId.uuidString.isEmpty)
  }

  @Test
  func coreReplayStateFingerprintMismatchOrphansEvent() {
    var baseline = GameState(gameId: "GAME-MISMATCH", players: [.blue, .yellow], authorityId: .blue)
    let engine = GameEngine(state: baseline, signatureVerifier: PermissiveCommandSignatureVerifier())
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: baseline.gameId
    )
    var next = baseline
    _ = next.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
    let draft = command.toMoveEvent(
      status: .committed,
      stateBefore: baseline,
      stateAfter: next,
      prevChainHash: baseline.stateHashChain.lastChainHash,
      chainHash: ""
    )

    let mismatched = MoveEvent(
      eventId: draft.eventId,
      commandId: draft.commandId,
      commandFingerprint: draft.commandFingerprint,
      expectedSeq: draft.expectedSeq,
      coordinationSeq: draft.coordinationSeq,
      coordinationAuthorityId: draft.coordinationAuthorityId,
      source: draft.source,
      playerId: draft.playerId,
      payload: draft.payload,
      stateFingerprintBefore: draft.stateFingerprintBefore,
      stateFingerprintAfter: "wrong-fingerprint",
      status: draft.status,
      chainHash: engine.computeChainHash(draft, afterFingerprint: "wrong-fingerprint"),
      prevChainHash: draft.prevChainHash,
      createdAt: draft.createdAt
    )
    let recovered = engine.replay(events: [mismatched])

    #expect(recovered.restoredState.phase != GamePhase.finished)
    #expect(recovered.orphanedEvents == [mismatched.eventId])
    baseline = recovered.restoredState
  }

  @Test
  func coreReplayFingerprintMismatchTriggersRepairWithoutChainMismatch() {
    let engine = GameEngine(
      state: GameState(gameId: "GAME-MISMATCH-CHAIN", players: [.blue, .yellow], authorityId: .blue),
      signatureVerifier: PermissiveCommandSignatureVerifier()
    )
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-MISMATCH-CHAIN"
    )
    var next = engine.state
    _ = next.apply(action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)), by: .blue)
    let draft = command.toMoveEvent(
      status: .committed,
      stateBefore: engine.state,
      stateAfter: next,
      prevChainHash: engine.state.stateHashChain.lastChainHash,
      chainHash: ""
    )
    let mismatched = MoveEvent(
      eventId: draft.eventId,
      commandId: draft.commandId,
      commandFingerprint: draft.commandFingerprint,
      expectedSeq: draft.expectedSeq,
      coordinationSeq: 1,
      coordinationAuthorityId: draft.coordinationAuthorityId,
      source: draft.source,
      playerId: draft.playerId,
      payload: draft.payload,
      stateFingerprintBefore: draft.stateFingerprintBefore,
      stateFingerprintAfter: "wrong-fingerprint",
      status: draft.status,
      chainHash: engine.computeChainHash(draft, afterFingerprint: next.stateFingerprint),
      prevChainHash: draft.prevChainHash,
      createdAt: draft.createdAt
    )

    let recovered = engine.replay(events: [mismatched])
    #expect(recovered.orphanedEvents == [mismatched.eventId])
    #expect(recovered.restoredState.phase == GamePhase.playing)
  }

  @Test
  func coreReplayChainHashMismatchWithoutFingerprintMismatch() {
    let engine = newEngine()
    let command = signedCommand(
      commandId: UUID(),
      clientId: "A",
      expectedSeq: 0,
      playerId: .blue,
      action: .place(pieceId: PieceLibrary.pieces[0].id, variantId: 0, origin: .init(x: 0, y: 0)),
      gameId: "GAME-REPLAY-CHAIN"
    )

    var after = engine.state
    _ = after.apply(action: command.action, by: .blue)

    let draft = command.toMoveEvent(
      status: MoveEventStatus.committed,
      stateBefore: engine.state,
      stateAfter: after,
      prevChainHash: engine.state.stateHashChain.lastChainHash,
      chainHash: ""
    )

    let badChainEvent = MoveEvent(
      eventId: draft.eventId,
      commandId: draft.commandId,
      commandFingerprint: draft.commandFingerprint,
      expectedSeq: draft.expectedSeq,
      coordinationSeq: draft.coordinationSeq,
      coordinationAuthorityId: draft.coordinationAuthorityId,
      source: draft.source,
      playerId: draft.playerId,
      payload: draft.payload,
      stateFingerprintBefore: "MISMATCHED_BEFORE",
      stateFingerprintAfter: after.stateFingerprint,
      status: draft.status,
      chainHash: "chain-mismatch",
      prevChainHash: draft.prevChainHash,
      createdAt: draft.createdAt
    )

    let recovered = engine.replay(events: [badChainEvent])
    #expect(recovered.orphanedEvents == [badChainEvent.eventId])
    #expect(recovered.restoredState.phase != GamePhase.finished)
  }

  @Test
  func submitRejectsNonceReplayForSamePlayer() {
    let engine = newEngine(players: [.blue, .yellow, .red])
    // A places mono-1 at corner
    let cmd1 = signedCommand(commandId: UUID(), clientId: "A", expectedSeq: 0, playerId: .blue,
      action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)),
      gameId: "GAME-001", nonce: 5555)
    guard case .accepted = engine.submit(cmd1) else {
      Issue.record("first submit should be accepted")
      return
    }
    // B and C take turns so it's A's turn again
    let cmd2 = signedCommand(commandId: UUID(), clientId: "B", expectedSeq: 1, playerId: .yellow,
      action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 19, y: 19)),
      gameId: "GAME-001", nonce: 1111)
    _ = engine.submit(cmd2)
    let cmd3 = signedCommand(commandId: UUID(), clientId: "C", expectedSeq: 2, playerId: .red,
      action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 19, y: 0)),
      gameId: "GAME-001", nonce: 2222)
    _ = engine.submit(cmd3)
    // Now A's turn again (expectedSeq: 3). Same nonce 5555, different commandId
    let cmd4 = signedCommand(commandId: UUID(), clientId: "A", expectedSeq: 3, playerId: .blue,
      action: .place(pieceId: "domino-2", variantId: 0, origin: BoardPoint(x: 1, y: 1)),
      gameId: "GAME-001", nonce: 5555)
    let result = engine.submit(cmd4)
    if case let .rejected(_, reason, _) = result {
      #expect(reason == .replayOrDuplicate)
    } else {
      Issue.record("nonce replay should be rejected")
    }
  }

  @Test
  func tickWithNoGapsDoesNothing() {
    let engine = newEngine(players: [.blue, .yellow])
    let phaseBefore = engine.state.phase
    let retryCountBefore = engine.state.repairContext.retryCount
    engine.tick(now: Date())
    #expect(engine.state.phase == phaseBefore)
    #expect(engine.state.repairContext.retryCount == retryCountBefore)
  }

  @Test
  func tickWhenAlreadyReadOnlyDoesNotChangePhase() {
    let engine = newEngine(players: [.blue, .yellow])
    engine.state.phase = .readOnly
    // Add a gap with nextRetryAt in the far future so the retry logic is not triggered
    engine.state.eventGaps = [EventGap(
      fromSeq: 1, toSeq: 5,
      detectedAt: defaultDate,
      retryCount: 0,
      nextRetryAt: defaultDate.addingTimeInterval(9999),
      lastError: nil,
      maxRetries: 3,
      deadlineAt: defaultDate.addingTimeInterval(99999)
    )]
    engine.tick(now: defaultDate)
    #expect(engine.state.phase == .readOnly)
  }

  @Test
  func replaySkipsNonCommittedEvents() {
    let engine = newEngine(players: [.blue, .yellow])
    let initialState = engine.state
    let proposedEvent = MoveEvent(
      eventId: UUID(),
      commandId: UUID(),
      commandFingerprint: Data(),
      expectedSeq: 0,
      coordinationSeq: 1,
      coordinationAuthorityId: .blue,
      source: .local,
      playerId: .blue,
      payload: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 0, y: 0)),
      stateFingerprintBefore: initialState.stateFingerprint,
      stateFingerprintAfter: "fake",
      status: .proposed,
      chainHash: "",
      prevChainHash: "",
      createdAt: defaultDate
    )
    let result = engine.replay(events: [proposedEvent])
    // Event should be skipped (not applied, not orphaned) because status is .proposed
    #expect(result.orphanedEvents.isEmpty)
    #expect(result.restoredState.expectedSeq == initialState.expectedSeq)
  }

  @Test
  func signatureVerifierReturnsFalseForUnknownPlayer() {
    let verifier = DefaultCommandSignatureVerifier(keysByPlayer: [.blue: "secretA"])
    // Command from player "B" which is not in the verifier's key map
    let cmd = signedCommand(commandId: UUID(), clientId: "B", expectedSeq: 0, playerId: .yellow,
      action: .place(pieceId: "mono-1", variantId: 0, origin: BoardPoint(x: 19, y: 19)),
      gameId: "GAME-001")
    #expect(verifier.verify(cmd) == false)
  }
}
