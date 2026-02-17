## GameState.swift からルール検証ロジックを PlacementValidator に抽出する

`Sources/Domain/GameState.swift`（230 LOC）が状態コンテナとBlokusルール検証（`canPlace`, `hasAnyLegalMove`）を兼任している。Single Responsibility Principle に違反。

- `Sources/Domain/PlacementValidator.swift` を新規作成
- `canPlace(pieceId:variantId:origin:playerId:)` ロジックを移動
- `hasAnyLegalMove` ロジックを移動
- `GameState` は純粋な状態コンテナとして残す
- 既存の呼び出し元（Engine, Features）を新しい API に切り替える
- ビルド確認・テストパスを確認する

## GameEngine.swift を責務ごとのサービスに分割する

`Sources/Engine/GameEngine.swift`（341 LOC）が以下の責務を全て担っている:
- コマンドバリデーション
- イベント生成
- リプレイロジック
- ギャップ管理
- レート制限

以下のサービスに分割する:
- `CommandValidator.swift` - コマンド検証ロジック
- `EventReplayService.swift` - イベントリプレイ・状態再構築
- `GapManager.swift` - ギャップ検出・リコンシリエーション
- `GameEngine.swift` - オーケストレーション層として残す（各サービスを組み合わせ）

既存テストがパスすること、public API に破壊的変更がないことを確認する。

## PersistenceStore.swift をリポジトリパターンで分割する

`Sources/Persistence/PersistenceStore.swift`（676 LOC）が DDL、マイグレーション、CRUD、クエリ、リカバリ全てを含んでいる。

以下に分割する:
- `MigrationManager.swift` - スキーママイグレーション管理
- `GameRepository.swift` - ゲーム状態の CRUD
- `EventRepository.swift` - イベントの CRUD（inbox_events, orphan_events 含む）
- `PersistenceStore.swift` - ファサードとして残し、各リポジトリを統合

`PersistenceStore+Audit.swift` は既に分割済みなのでそのまま。ビルド確認・テストパスを確認する。

## Magic Numbers を定数化し Board 型を導入する

コードベース全体に散在するマジックナンバーと、プリミティブな `[PlayerID?]` 配列を改善する。

1. **定数化**:
   - `Sources/Domain/BoardConstants.swift` を作成
   - ボードサイズ `20×20`、セル数 `400` を定数化
   - `GameEngine` のレート制限値、リトライ回数等も設定型に抽出

2. **Board 型の導入**:
   - `Sources/Domain/Board.swift` に `Board` struct を定義
   - `subscript(point: BoardPoint) -> PlayerID?` で座標アクセス
   - `GameState.board` の型を `[PlayerID?]` → `Board` に変更

3. 全ての既存参照箇所（Domain, Engine, Features）を新しい定数・型に移行

ビルド確認・テストパスを確認する。
