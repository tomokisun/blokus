# Training Architecture (Mac mini M4)

最終更新: 2026-02-20

## 目的

- iPhone配布モデルを作るために、自己対戦データ生成を macOS 側で高速実行する。
- 既存モジュール (`Domain`, `Engine`) のルールを学習にもそのまま適用し、実機挙動とのズレをなくす。

## 実装モジュール

- `AICore`
  - `LegalMoveGenerator`: アンカーベース合法手列挙と候補上限適用
  - `HeuristicPolicyValuePredictor`: 方策事前分布と価値近似（ヒューリスティック）
  - `LearnedPolicyValuePredictor`: 学習済みモデルによる方策・価値推論（MLP/CNN/線形対応）
  - `MCTSAgent`: PUCT探索（`applyUnchecked` による高速シミュレーション）
  - `SelfPlayRunner`: 並列自己対戦実行（temperature drop 対応）
  - `TrainingDataWriter`: NDJSON + metadata 出力
  - `BoardFeatureExtractor`: 盤面から21特徴量を抽出（MLP/CNN入力用）
  - `NeuralNetwork`: MLP・CNN の順伝播・逆伝播・ミニバッチSGD学習（純Swift実装）
  - `DataAugmentation`: 8倍対称性変換（4回転×2反転）によるデータ拡張
- `TrainerCLI`
  - `selfplay` サブコマンドで学習データ生成を実行（学習済みモデルでの自己対戦対応）
  - `train` サブコマンドで学習済みモデルを生成（linear/mlp/cnn アーキテクチャ選択）
  - `eval` サブコマンドでモデル比較評価を実行
  - `export` サブコマンドで配布向け推論バンドルを出力
  - 実行中に進捗ログ (`[progress] ...`) を継続表示

## モデルアーキテクチャ

### linear（v1 互換）

- **方策**: アクションバイアステーブル + ピースバイアス + パスバイアス（ヒューリスティックとのブレンド）
- **価値**: 4特徴量（intercept, lead, progress, occupancy）の線形回帰 + プレイヤーバイアス
- 高速だが表現力に限界あり

### mlp（推奨）

- **方策**: linear と同じバイアステーブル方式
- **価値**: 盤面から21特徴量を抽出 → 2層MLP（64→32→1, ReLU）
- 特徴量: プレイヤーごとのセル数・アンカー数・エッジ数、リード、充填率、重心距離など
- 推論速度: 数μs/予測（MCTS内で実用的）
- 学習速度: 800Kポジション × 20エポック ≈ 2.5分

### cnn（実験的）

- **方策**: linear と同じバイアステーブル方式
- **価値**: 20×20×4チャンネル（プレイヤー占有マップ）→ Conv2D(8ch)×2 → GAP → Dense(32→1)
- 空間パターンを直接学習可能
- 推論速度: MLP より遅い（MCTS内では小規模CNN推奨）

### モデルJSON形式（v2）

v1 フィールドに加え、以下のオプショナルフィールドを追加:
- `architecture`: `"mlp"` / `"cnn"` （省略時は `"linear"`）
- `mlpWeights`: MLP層の重み・バイアス
- `cnnWeights`: Conv2D層 + Dense層の重み

v1 モデルのデコードとの後方互換性を維持。

## 自己対戦パイプライン

1. `SelfPlayRunner` がゲームIDを採番してゲーム初期化 (`GameState`)。
2. 序盤 N 手は `temperature=1.0` で探索多様性を確保（`--temperature-drop`）。以降は `temperature=0` で最善手。
3. 各手で `MCTSAgent.decide` を実行。`applyUnchecked` でバリデーション省略の高速シミュレーション。
4. `selectedAction` を `GameState.apply` で適用。
5. 各局終了後、最終盤面スコアを `outcomeByPlayer` として全ポジションへ付与。
6. `TrainingDataWriter` で `positions.ndjson` / `games.ndjson` / `metadata.json` を保存。
7. `--model` 指定時は学習済み `LearnedPolicyValuePredictor` を使用（指定なしはヒューリスティック）。

## 学習パイプライン

1. `train` がポジションデータを読み込み（`--data` + `--data-extra` で累積データ対応）
2. `--augment` 指定時: 8倍対称性変換（4回転×2反転）でデータ拡張
3. 方策バイアステーブルの構築（全アーキテクチャ共通）
4. 価値モデルの学習:
   - `linear`: 正規方程式による線形回帰
   - `mlp`: `BoardFeatureExtractor` で21特徴量抽出 → ミニバッチSGDで2層MLP学習
   - `cnn`: 20×20×4チャンネル構築 → ミニバッチSGDでCNN学習
5. モデルJSON出力（v2形式: 線形回帰 + ニューラルネット重みの両方を保持）

## データ拡張

ブロックスの20×20盤面は正方形のため、以下の8つの対称性変換が適用可能:
- 恒等変換 / 90°回転 / 180°回転 / 270°回転
- 水平反転 / 水平反転+90° / 水平反転+180° / 水平反転+270°

各変換で盤面・選択手・方策分布を正しく変換（ピースvariant対応あり）。
データ量が8倍になり、学習の汎化性能が向上。

## 累積リプレイバッファ

- `--data-extra` で過去サイクルのデータを追加読み込み
- Makefile の `TRAIN_CUMULATIVE_WINDOW` で直近N回分を自動マージ
- 複数サイクルのデータを蓄積することで、学習の安定性と多様性が向上

## MCTS設定項目

- `simulations`: 1手あたり探索反復数
- `explorationConstant`: PUCT の探索係数（デフォルト 1.25）
- `maxCandidateMoves`: 展開候補の上限
- `temperature`: ルート行動サンプリング温度
- `temperatureDropPly`: 序盤N手は温度1.0で探索（AlphaZero方式）

## CLIパラメータ

### selfplay

- `--games`: 対局数
- `--players`: プレイヤー数 (2...4)
- `--simulations`: 探索回数
- `--max-candidates`: 候補手数上限
- `--max-turns`: 1局の最大手数
- `--parallel`: 並列ワーカー数
- `--temperature`: ルート温度
- `--temperature-drop`: 序盤N手のみtemp=1.0で探索
- `--seed`: 乱数シード
- `--output`: 出力ディレクトリ
- `--model`: 学習済みモデルパス（指定時は学習済みpredictorを使用）

### train

- `--data`: 学習データパス（必須）
- `--data-extra`: 追加データパス（累積リプレイバッファ、複数指定可）
- `--output`: モデル出力先
- `--limit`: 読み込むポジション数上限
- `--label`: モデル名ラベル
- `--architecture`: `linear` / `mlp` / `cnn`（デフォルト: `linear`）
- `--policy-blend`: 方策ブレンド比 (0-1)
- `--value-blend`: 価値ブレンド比 (0-1)
- `--selected-boost`: 選択手バイアス強化量
- `--max-action-biases`: 保存するアクションバイアス数
- `--ridge`: L2正則化（線形回帰用）
- `--epochs`: MLP/CNNエポック数
- `--lr`: MLP/CNN学習率
- `--batch-size`: MLP/CNNバッチサイズ
- `--augment`: 8倍対称性データ拡張を有効化

## 出力フォーマット

### positions.ndjson (1行1局面)

- `gameId`: 局ID
- `ply`: 手数インデックス
- `activePlayer`: 手番プレイヤー
- `boardEncoding`: 20x20盤面のフラット配列 (`0:空き, 1...:turnOrder index + 1`)
- `selectedAction`: 採用手
- `selectedActionKey`: 採用手のキー表現 (`P|piece|variant|x|y` / `PASS`)
- `policy`: ルート訪問回数由来の確率分布
- `outcomeByPlayer`: 最終アウトカム

### games.ndjson (1行1対局)

- `gameId`
- `turns`
- `winnerIds`
- `scores`

### metadata.json

- 実行時刻、所要時間、設定、データ件数

## 次段階

1. `PolicyValuePredicting` を Core ML 推論実装に差し替え（MLP/CNN対応）
2. 終盤完全探索ハイブリッド
3. より大きなCNNアーキテクチャ（Accelerateフレームワーク活用）
