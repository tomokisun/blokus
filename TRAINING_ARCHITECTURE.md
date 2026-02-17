# Training Architecture (Mac mini M4)

## 目的

- iPhone配布モデルを作るために、自己対戦データ生成を macOS 側で高速実行する。
- 既存モジュール (`Domain`, `Engine`) のルールを学習にもそのまま適用し、実機挙動とのズレをなくす。

## 実装モジュール

- `AICore`
  - `LegalMoveGenerator`: 合法手列挙と候補上限適用
  - `HeuristicPolicyValuePredictor`: 方策事前分布と価値近似
  - `MCTSAgent`: PUCT探索
  - `SelfPlayRunner`: 並列自己対戦実行
  - `TrainingDataWriter`: NDJSON + metadata 出力
- `TrainerCLI`
  - `selfplay` サブコマンドで学習データ生成を実行
  - `train` サブコマンドで学習済みモデルを生成
  - `eval` サブコマンドでモデル比較評価を実行
  - `export` サブコマンドで配布向け推論バンドルを出力
  - 実行中に進捗ログ (`[progress] ...`) を継続表示

## 自己対戦パイプライン

1. `SelfPlayRunner` がゲームIDを採番してゲーム初期化 (`GameState`)。
2. 各手で `MCTSAgent.decide` を実行。
3. `selectedAction` を `GameState.apply` で適用。
4. 各局終了後、最終盤面スコアを `outcomeByPlayer` として全ポジションへ付与。
5. `TrainingDataWriter` で `positions.ndjson` / `games.ndjson` / `metadata.json` を保存。

## MCTS設定項目

- `simulations`: 1手あたり探索反復数
- `explorationConstant`: PUCT の探索係数
- `maxCandidateMoves`: 展開候補の上限
- `temperature`: ルート行動サンプリング温度

## CLIパラメータ

- `--games`: 対局数
- `--players`: プレイヤー数 (2...4)
- `--simulations`: 探索回数
- `--max-candidates`: 候補手数上限
- `--max-turns`: 1局の最大手数
- `--parallel`: 並列ワーカー数
- `--temperature`: ルート温度
- `--seed`: 乱数シード
- `--output`: 出力ディレクトリ

## 出力フォーマット

### positions.ndjson (1行1局面)

- `gameId`: 局ID
- `ply`: 手数インデックス
- `activePlayer`: 手番プレイヤー
- `boardEncoding`: 20x20盤面のフラット配列 (`0:空き, 1...:turnOrder index + 1`)
- `selectedAction`: 採用手
- `policy`: ルート訪問回数由来の確率分布
- `outcomeByPlayer`: 最終アウトカム

### games.ndjson (1行1対局)

- `gameId`
- `turns`
- `winnerIds`
- `scores`

### metadata.json

- 実行時刻、所要時間、設定、生成件数

## 次段階（未実装）

1. `PolicyValuePredicting` を Core ML 推論実装に差し替え
2. 学習ループ (PyTorch/MLX) との反復統合
3. 終盤完全探索ハイブリッド
