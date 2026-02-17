## 完了タスク

### 2026-02-17: DomainTypes.swift 分割
- DomainTypes.swift を Player.swift, BoardPoint.swift, Piece.swift, Commands.swift, Events.swift, GamePhase.swift, Coordination.swift に分割
- ビルド・89テスト全パス

### 2026-02-18: PlacementValidator 抽出
- GameState.swift からルール検証ロジック（canPlace, hasAnyLegalMove）を PlacementValidator.swift に抽出
- GameState は PlacementValidator への委譲メソッドで後方互換性を維持
- boardPointSafe を GameState から削除（PlacementValidator に移動）
- ビルド・89テスト全パス

### 2026-02-18: GameEngine.swift 責務分割
- GameEngine.swift（341→168 LOC）をオーケストレーション層に縮小
- CommandValidator.swift 抽出: コマンド検証・レート制限・nonce/重複チェック
- EventReplayService.swift 抽出: イベントリプレイ・状態再構築
- GapManager.swift 抽出: ギャップ検出・登録・リトライスケジューリング
- queued ケースで GapManager.registerGap 後の更新済み state を返すバグを修正
- ビルド・89テスト全パス

### 2026-02-18: PersistenceStore.swift リポジトリパターン分割
- PersistenceStore.swift（676→200 LOC）をファサード+SQLiteヘルパーに縮小
- PersistenceStore+Migration.swift 抽出: bootstrap, migrateSchema, migrate（スキーマDDL全体）
- PersistenceStore+GameRepository.swift 抽出: upsertGame, loadGame, rebuild, readOnlyContext, loadOperationalMetrics
- PersistenceStore+EventRepository.swift 抽出: upsertEvent, insertGap, clearGaps, syncEventGaps, loadEventGaps, loadCommittedEvents, appendOrphan, appendAuditLog, appendInboxEvent
- private プロパティ（db, encoder, decoder）とヘルパーメソッドを internal に変更し extension からアクセス可能に
- 既存の PersistenceStore+Audit.swift はそのまま維持
- ビルド・89テスト全パス

### 2026-02-18: Magic Numbers 定数化 + Board 型導入
- BoardConstants.swift 作成: boardSize(20), boardCellCount(400), maxBoardIndex(19), playerStartCorners を定数化
- Board struct 導入: [PlayerID?] をラップし subscript(point:BoardPoint) と subscript(index:Int) で型安全なアクセスを提供
- Board.index(_:) / Board.boardPoint(for:) で座標⇔インデックス変換を集約
- GameState.board の型を [PlayerID?] → Board に変更
- Domain（PlacementValidator, BoardPoint）、Engine（GapManager）、Features（BoardView, GameViewModel）の全参照箇所を BoardConstants に移行
- GapManager の operational 定数（initialRetryDelaySec, maxRetries, deadlineWindowSec, maxBackoffSec）も名前付き定数化済み
- ビルド・89テスト全パス

### 2026-02-18: RemoteEventProcessor 抽出
- Replication.swift（243→17 LOC）を薄い委譲ラッパーに縮小
- RemoteEventProcessor.swift 作成: ForkEventRecord, RemoteIngestResult（committedEvents追加）, process() を抽出
- makeGap/markExistingGapOrCreate を削除し GapManager.registerGap に統合（DRY違反解消）
- buildCommittedEventFromRemote を RemoteEventProcessor の private static ヘルパーに移動
- PersistenceStore+Audit.swift の applyRemoteResult: engine.events 線形検索を result.committedEvents に改善
- ビルド・89テスト全パス
