# Blokus TCA+Dependencies 実装チェックリスト

## 0. 準備
- [ ] `Package.swift` の変更をコミット対象にするかを確認する
- [ ] `swift-composable-architecture` の導入有無を確認し、なければ追加する
- [ ] `Dependencies` の導入有無を確認し、なければ追加する
- [ ] `DependenciesTestSupport` の導入有無を確認し、なければテストターゲットに追加する
- [ ] `swift-testing` をテストターゲットで使える状態にする
- [ ] `Xcode` のスキームで新規依存更新をビルド反映できるかを確認する

## 1. 依存注入の土台
- [ ] `DependencyValues` に `aiEngineClient` 用キーを追加する
- [ ] `DependencyValues` に `auditLogger` 用キーを追加する
- [ ] `DependencyValues` に `deterministicClock` 用キーを追加する
- [ ] `DependencyValues` に `uuid` / `date` / `uuid` が既存利用なら差し替え規則を確認する
- [ ] `AIEngineClient` の `DependencyKey` 実装を作成する
- [ ] 本番 `AIEngineClient.liveValue` を実装する
- [ ] テスト用 `AIEngineClient.testValue` を実装する
- [ ] `App` 起点で `prepareDependencies` を呼ぶ初期化を追加する
- [ ] プレビュー内でも依存上書きを使える共通ヘルパーを作る

## 2. Domain モデルの再設計
- [ ] `TurnTicket` を `SessionID/turnIndex/revision/requestSequence/stateDigest/schemaVersion` に拡張する
- [ ] `DeterministicKey` を追加する
- [ ] `SearchBudget` を追加する
- [ ] `AIMoveError` を 5 パターン以上含む enum で明示する
- [ ] `AIMoveRequest` の `requestId` / `ticket` / `deadline` を保持する
- [ ] `AIMoveResult = Result<MoveDecision, AIMoveError>` の型定義を追加する
- [ ] `MoveDecision` を `place / pass(PassReason)` で定義する
- [ ] `AIFallbackPolicy` を `failTurnAndRetry / failFast / pauseForHuman` で定義する
- [ ] `CancelReason` を追加して廃棄/タイムアウト系を型で追えるようにする

## 3. GameFeature と UI 結線
- [ ] `RootFeature` の `State` に `game: GameFeature.State` を追加する
- [ ] `RootFeature` の `Action` を `game` 連携に絞って定義する
- [ ] `RootFeature` の `body` を `Scope` ベースにする
- [ ] `GameFeature.State` の AI 実行関連フラグを追加する
- [ ] `GameFeature.State` の `@Presents` 用 alert state を追加する
- [ ] `GameFeature.Action` に `turnCoordinator` 遷移アクションを追加する
- [ ] `GameView` の `store` を `StoreOf<GameFeature>` に統一する
- [ ] `@Bindable var store: StoreOf<GameFeature>` へ差し替える
- [ ] `send` 先をすべて `Action` 経由に統一する
- [ ] 盤面操作のUIイベントを reducer Action に変換する

## 4. TurnCoordinator の実装
- [ ] `TurnCoordinator.State` を `ticket / inFlight / queueDepth / status` で再定義する
- [ ] `TurnCoordinator.Action` を `launchIfNeeded / aiResponse / receiveAIResult / cancelInFlight` に整理する
- [ ] `@Dependency(\.date.now)` と `@Dependency(\.clock)` と `@Dependency(AIEngineClient.self)` を注入する
- [ ] `launchIfNeeded` で AI 手番のみ実行する guard を追加する
- [ ] `launchIfNeeded` で既存タスクを `.cancel` する分岐を追加する
- [ ] `buildRequest` で `requestSequence` をインクリメントする
- [ ] `TaskResult` を使う AI 呼び出しパスを実装する
- [ ] `CancelID.aiInFlight` を定義する
- [ ] `receiveAIResult` の受理条件4点を全件検証する
- [ ] 受理不可時に `discarded` ログを残し状態を変えない
- [ ] 遅延到着（late result）を検知して監査のみ記録する
- [ ] 成功時に `MoveDecision` を `state` へ反映する reducer を追加する
- [ ] 失敗時に `AIFallbackPolicy` を実行する分岐を追加する

## 5. タイムアウトと再試行
- [ ] `softTimeout` 到達時の遷移を分離して実装する
- [ ] `hardTimeout` 到達時のエラーを `AIMoveError` 化する
- [ ] AI タイムアウトを `failTurnAndRetry` として扱う
- [ ] 同一要求連続失敗カウンタを `State` に追加する
- [ ] 失敗連続時に `pauseForHuman` へ遷移する閾値を追加する
- [ ] リトライ時に `backoffMillis` を反映する
- [ ] `cancelInFlight` で `inFlight` 状態を必ずクリーンアップする

## 6. 監査とログ
- [ ] `AuditEvent` と相関キー `session:turn:requestSequence:requestId` を追加する
- [ ] `Critical` / `Event` / `Debug` の3層チャネル定義を追加する
- [ ] `turn.started` を必須ログとして追加する
- [ ] `ai.requested` を必須ログとして追加する
- [ ] `ai.received / ai.discarded / ai.applied / move.failed / ai.timeout.*` を追加する
- [ ] `critical` を永続化キューへ流すルートを実装する
- [ ] `debug` をリングバッファへ流す実装を追加する
- [ ] 監査イベントに `schemaVersion` と `stateDigest` を添付する

## 7. AI エンジン契約
- [ ] `AIEngineClient` の `nextMove` で `Task.checkCancellation()` 呼び出し要件を明文化する
- [ ] 非協調実装を検知するための実装コメントと実装テストを付ける
- [ ] `GameState` 全体ではなく snapshot 型に投影して受ける
- [ ] 乱数シード順序、ソート順序、列挙順の再現規則を固定する
- [ ] `stateDigest` 生成関数を 1 箇所に集約する

## 8. テスト（swift-testing）
- [ ] `TestStore` のセットアップ雛形を追加する
- [ ] `Date` / `UUID` / `AIEngine` を `.dependencies` で固定値化する
- [ ] stale（不一致）応答が破棄されるテストを追加する
- [ ] late（期限超過）応答が破棄されるテストを追加する
- [ ] soft/hard timeout 遷移テストを追加する
- [ ] failFast / failTurnAndRetry / pauseForHuman 切替テストを追加する
- [ ] determinism テスト（同一 key + 同一 state で同一結果）を追加する
- [ ] `Task.checkCancellation()` 未実装時に落ちるテストを追加する
- [ ] 監査イベント必須キーの欠落を検知するテストを追加する

## 9. CI / 品質ゲート
- [ ] `Task.detached` 禁止ルールを追加する
- [ ] `unsafeBitCast` 禁止ルールを追加する
- [ ] 無断 `sleep` / `try?` の例外ルールを追加する
- [ ] 層依存違反の検知ルールを追加する
- [ ] 重要監査イベント欠落時に CI が失敗するルールを追加する
- [ ] 上記チェックを最小 2 件組み合わせて PR ゲート化する

## 10. 最終接続
- [ ] 新規 `GameState` 書込経路を唯一 `TurnCoordinator` の reducer に寄せる
- [ ] 既存の直接更新箇所を reducer イベント化して削除する
- [ ] DI の初期値と preview 用値を統一して再現性を確認する
- [ ] `ARCHITECTURE.md` の記載と実装タスクの差分を突合する
- [ ] 1 画面フロー分（1ゲーム）で手動動作検証を行う
- [ ] 主要テストを全件通過させる
