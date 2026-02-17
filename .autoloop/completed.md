## 完了タスク

### 2026-02-17: DomainTypes.swift 分割
- DomainTypes.swift を Player.swift, BoardPoint.swift, Piece.swift, Commands.swift, Events.swift, GamePhase.swift, Coordination.swift に分割
- ビルド・89テスト全パス

### 2026-02-18: PlacementValidator 抽出
- GameState.swift からルール検証ロジック（canPlace, hasAnyLegalMove）を PlacementValidator.swift に抽出
- GameState は PlacementValidator への委譲メソッドで後方互換性を維持
- boardPointSafe を GameState から削除（PlacementValidator に移動）
- ビルド・89テスト全パス
