## Replication.swift から RemoteEventProcessor を抽出し GapManager とギャップ生成ロジックを統合する

`Sources/Engine/Replication.swift`（243 LOC）は GameEngine の extension として remote event 取り込みを行っているが、独立した責務である。既に抽出済みの `CommandValidator`、`EventReplayService`、`PlacementValidator` と同じパターンで分割する。

1. **RemoteEventProcessor 抽出**:
   - `Sources/Engine/RemoteEventProcessor.swift` を作成
   - `applyRemoteEvents()` ロジックを GameEngine extension から移動
   - `buildCommittedEventFromRemote()` ファクトリメソッドも移動
   - GameEngine は RemoteEventProcessor への委譲で後方互換性を維持

2. **GapManager との統合**:
   - `Replication.swift` の `makeGap()` / `markExistingGapOrCreate()` のギャップ生成ロジックを `GapManager` に集約
   - 重複する定数（`maxRetries: 5`、`deadlineAt: 31秒`、`nextRetryAt: 1秒`）を `GapManager` の単一定義に統合（DRY違反の解消）

ビルド確認・89テスト全パスを確認する。

## PersistenceStore+Audit.swift の applySubmitResult / applyRemoteResult を OperationalConnector に移動する

`PersistenceStore+Audit.swift`（223 LOC）の `applySubmitResult()` と `applyRemoteResult()` メソッドは、`GameEngine` を引数として受け取り、エンジンの内部状態に依存したオーケストレーションロジックを含んでいる。これは永続化層がエンジン層に依存するアーキテクチャ逆転を起こしている。

1. **OperationalConnector への移動**:
   - `applySubmitResult()` と `applyRemoteResult()` のオーケストレーションロジックを `OperationalConnector.swift` に移動
   - PersistenceStore には純粋な永続化操作（`persistEvent()`、`updateAuditLog()` 等）のみを残す
   - OperationalConnector が Engine と Persistence を適切に調整する形に修正

2. **依存方向の正常化**:
   - PersistenceStore から GameEngine への依存を除去
   - Connector → Engine, Connector → Persistence の一方向依存に統一

ビルド確認・89テスト全パスを確認する。

## デッドコード削除と冗長コードのクリーンアップ

コードベース内に発見された不要コードと冗長な記述を整理する。

1. **EventReplayService.swift のデッドコード削除**:
   - `replay()` メソッド内の未使用 `MoveEvent` 構築（構築後 `_` に代入されて破棄されている）を削除

2. **GameEngine.swift の冗長コード整理**:
   - `submit()` 内の `events.count == Int.max ? UUID() : UUID()` ノーオプ三項演算子を単純な `UUID()` に修正
   - `knownCommands` 設定直後の `if let _ = committed` ガードが常に成功する冗長チェックを簡素化

3. **CanonicalWriter.swift の重複プロパティ統一**:
   - `Data.hexString` と `Data.hex` が完全に同一実装で共存しているため、一方に統一
   - 全呼び出し箇所を統一後のプロパティ名に移行

ビルド確認・89テスト全パスを確認する。

## GameViewModel.swift の canonicalize 重複を解消しピース操作ロジックを Domain 層に移動する

`GameViewModel.swift`（260 LOC）の private `canonicalize()` メソッドが `Piece.swift` の `PieceVariantsCache.canonicalize()` と完全に同一実装になっている。

1. **canonicalize の公開化**:
   - `Piece.swift` の `PieceVariantsCache.canonicalize()` を `Piece` または `BoardPoint` の public static メソッドとして公開
   - `GameViewModel.swift` の重複 `canonicalize()` を削除し、Domain 層のメソッドを使用

2. **ピース変換ヘルパーの Domain 層移動**:
   - `rotatePiece()` と `flipPiece()` のバリアント選択ロジックを `Piece` に `rotatedVariantIndex(from:)` / `flippedVariantIndex(from:)` として追加
   - GameViewModel はこれらを呼び出すだけの薄いラッパーに縮小

ビルド確認・89テスト全パスを確認する。

## PlacementValidator の直接ユニットテストを追加する

現在 `PlacementValidator` は `GameStateTests` と `EngineTests` を通じた間接テストしか存在しない。配置ルールの境界条件を直接テストするファイルを追加する。

1. **テストファイル作成**:
   - `Tests/BlokusAppTests/Domain/PlacementValidatorTests.swift` を作成

2. **テストケース**:
   - 初手制約（各プレイヤーの開始コーナーへの配置）
   - 角接触ルール（自色の角に接する配置のみ許可）
   - 辺隣接禁止ルール（自色の辺に隣接する配置の拒否）
   - ボード範囲外への配置拒否
   - `hasAnyLegalMove` の true/false 境界ケース
   - 複数ピースが重なる配置の拒否

ビルド確認・全テストパスを確認する。
