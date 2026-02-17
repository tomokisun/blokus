# Context

Magic Numbers 定数化 + Board 型導入が完了。次は Replication.swift から RemoteEventProcessor 抽出。

## アーキテクチャ
- Domain / Engine / Persistence / Connector / DesignSystem / Features の6モジュール
- Event Sourcing + CQRS パターン、State Machine、Repository パターン採用
- 外部依存なし（Pure Swift + Foundation + SwiftUI + SQLite3 + CryptoKit）

## 完了済みリファクタリング
1. **DomainTypes.swift 分割** - 6ファイルに分割完了（Player.swift, BoardPoint.swift, Piece.swift, Commands.swift, Events.swift, GamePhase.swift, Coordination.swift）。ビルド・89テスト全パス確認済み。
2. **PlacementValidator 抽出** - GameState.swift からルール検証ロジック（canPlace, hasAnyLegalMove）を PlacementValidator.swift に抽出。GameState は委譲メソッドで後方互換性を維持。ビルド・89テスト全パス確認済み。
3. **GameEngine.swift 責務分割** - GameEngine.swift（341→168 LOC）をオーケストレーション層に縮小。CommandValidator.swift、EventReplayService.swift、GapManager.swift を抽出。queued 時のステート返却バグも修正。ビルド・89テスト全パス確認済み。
4. **PersistenceStore.swift リポジトリパターン分割** - PersistenceStore.swift（676→200 LOC）をファサードに縮小。PersistenceStore+Migration.swift（スキーマDDL・マイグレーション）、PersistenceStore+GameRepository.swift（ゲーム状態CRUD・rebuild・metrics）、PersistenceStore+EventRepository.swift（イベント/ギャップ/オーファン/インボックス/監査CRUD）を抽出。ビルド・89テスト全パス確認済み。
5. **Magic Numbers 定数化 + Board 型導入** - BoardConstants.swift（boardSize, boardCellCount, maxBoardIndex, playerStartCorners）を作成。Board struct（subscript(point:), subscript(index:), index/boardPoint変換）を導入。GameState.board を [PlayerID?] → Board に変更。全参照箇所を BoardConstants に移行。GapManager の定数も名前付き定数化済み。ビルド・89テスト全パス確認済み。

## 残りのリファクタリング対象
6. **Replication.swift (243 LOC)** - GameEngine extension として remote event 取り込みを実装。GapManager とギャップ生成定数が重複
7. **PersistenceStore+Audit.swift のアーキテクチャ逆転** - applySubmitResult/applyRemoteResult が Engine に依存
8. **デッドコード・冗長コード** - EventReplayService の未使用 MoveEvent 構築、GameEngine のノーオプ三項演算子、CanonicalWriter の重複 hex プロパティ
9. **GameViewModel の canonicalize 重複** - Piece.swift と同一実装が Features 層にもある
10. **PlacementValidator のテスト不足** - 間接テストのみで直接ユニットテストが未整備

## 方針
- Phase 1: ファイル分割とサービス抽出（高優先度）← Replication が残り
- Phase 2: アーキテクチャ修正（中優先度）← Audit 移動
- Phase 3: コード品質・テスタビリティ向上（中優先度）← デッドコード削除 + canonicalize 統合 + テスト追加
