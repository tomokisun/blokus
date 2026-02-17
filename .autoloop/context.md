# Context

GameState.swift から PlacementValidator 抽出タスク完了。次は GameEngine.swift の責務分割。

## アーキテクチャ
- Domain / Engine / Persistence / Connector / DesignSystem / Features の6モジュール
- Event Sourcing + CQRS パターン、State Machine、Repository パターン採用
- 外部依存なし（Pure Swift + Foundation + SwiftUI + SQLite3 + CryptoKit）

## 完了済みリファクタリング
1. **DomainTypes.swift 分割** - 6ファイルに分割完了（Player.swift, BoardPoint.swift, Piece.swift, Commands.swift, Events.swift, GamePhase.swift, Coordination.swift）。ビルド・89テスト全パス確認済み。
2. **PlacementValidator 抽出** - GameState.swift からルール検証ロジック（canPlace, hasAnyLegalMove）を PlacementValidator.swift に抽出。GameState は委譲メソッドで後方互換性を維持。ビルド・89テスト全パス確認済み。

## 残りのリファクタリング対象
3. **GameEngine.swift (341 LOC)** - コマンド検証・イベント生成・リプレイ・ギャップ管理・レート制限が全部入り
4. **PersistenceStore.swift (676 LOC)** - DDL/マイグレーション/CRUD/クエリ/リカバリが混在
5. **Magic Numbers** - ボードサイズ 20×20 やリトライ回数がハードコーディング
6. **Board が primitive array** - `[PlayerID?]` の flat array で座標ラッパーなし

## 方針
- Phase 1: ファイル分割とサービス抽出（高優先度）
- Phase 2: Value Object 導入（中優先度）
- Phase 3: テスタビリティ向上（中優先度）
