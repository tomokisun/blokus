# トレーニング計画（Blokus AI）

最終更新: 2026-02-20

## 目的

- M4 Mac mini で自己対戦データを継続生成し、`selfplay -> train -> eval -> export` を反復して強化する。
- iPhoneアプリ側は軽量推論（最終的に CoreML）に寄せる。

## 反復ループ

1. `selfplay` でデータ生成（学習済みモデルによる自己対戦）
2. `train` でモデル学習（MLP推奨、データ拡張・累積データ活用）
3. `eval` で旧ベストモデルと比較
4. 勝率閾値（55%）を超えたらベストモデルを更新（`promote`）
5. `export` で配布用バンドル生成
6. iPhoneアプリへ統合して実機確認

## 自動化ループ

```bash
# 5サイクル連続実行（推奨）
make m4-loop LOOP_COUNT=5

# パラメータ調整例
make m4-loop LOOP_COUNT=10 PROMOTE_THRESHOLD=0.55 TRAIN_ARCHITECTURE=mlp
```

`scripts/loop.sh` が各サイクルで `selfplay → merge → train → eval → export` を実行し、
勝率が閾値を超えたモデルを自動プロモートする。

## モデルアーキテクチャの選択

| アーキテクチャ | 指定 | 価値モデル | 学習速度 | 推論速度 | 推奨場面 |
|:---:|:---:|:---|:---:|:---:|:---|
| linear | `TRAIN_ARCHITECTURE=linear` | 4特徴量の線形回帰 | 極速 | 極速 | ベースライン、初回 |
| **mlp** | `TRAIN_ARCHITECTURE=mlp` | **21特徴量 → 2層MLP (64→32→1)** | **~2.5分/800K** | **数μs** | **推奨** |
| cnn | `TRAIN_ARCHITECTURE=cnn` | 20×20×4ch → Conv2D×2 → Dense | 遅め | 遅め | 実験用 |

## データ強化オプション

### データ拡張（`--augment` / `TRAIN_AUGMENT=true`）

盤面の8倍対称性変換（4回転×2反転）を適用。ピースvariant・配置座標も正しく変換。
学習データが8倍に増え、汎化性能が向上する。

### 累積リプレイバッファ（`--data-extra` / `TRAIN_CUMULATIVE_WINDOW`）

過去サイクルのデータを追加で読み込み、複数サイクル分のデータで学習。
`TRAIN_CUMULATIVE_WINDOW=3` で直近3サイクル分を自動マージ。

## データ量の段階目標

1. 検証: 2,000局
2. ベースライン: 20,000局（shard×2, 10,000局/shard）
3. 強化: 100,000局+（累積データ活用）

## 推奨ディレクトリ運用

- 自己対戦: `TrainingRuns/<timestamp>/`
  - `shard-*/`: 各shardの自己対戦データ
  - `merged/`: shardを結合したデータ
- 学習モデル: `Models/model-<timestamp>.json`
- ベストモデル: `Models/model-best.json`
- 評価結果: `Reports/eval-<timestamp>.json`
- 配布用: `Exports/export-<timestamp>/`
- 自動化: `scripts/loop.sh`

## 実行テンプレート

### Make プリセット（推奨）

```bash
# 全パイプライン一括実行
make m4-all

# 個別実行
make m4-selfplay
make m4-merge
make m4-train
make m4-eval
make m4-export
make m4-promote  # ベストモデルを手動更新

# 自動ループ
make m4-loop LOOP_COUNT=5
```

### 手動実行

#### 1) 自己対戦

```bash
./.build/release/TrainerCLI selfplay \
  --games 10000 \
  --players 4 \
  --simulations 256 \
  --max-candidates 40 \
  --parallel 5 \
  --temperature-drop 20 \
  --model Models/model-best.json \
  --output TrainingRuns/run-001
```

#### 2) 学習（MLP + データ拡張 + 累積データ）

```bash
./.build/release/TrainerCLI train \
  --data TrainingRuns/run-001/merged \
  --data-extra TrainingRuns/run-000/merged \
  --architecture mlp \
  --epochs 20 \
  --lr 0.001 \
  --batch-size 256 \
  --augment \
  --label model-001 \
  --output Models/model-001.json
```

#### 3) 評価

```bash
./.build/release/TrainerCLI eval \
  --model-a Models/model-best.json \
  --model-b Models/model-001.json \
  --games 3000 \
  --players 4 \
  --simulations 160 \
  --parallel 10 \
  --seed 42 \
  --output Reports/eval-001.json
```

#### 4) 書き出し

```bash
./.build/release/TrainerCLI export \
  --model Models/model-001.json \
  --output Exports/export-001
```

## 昇格判定ルール

`scripts/loop.sh` での自動判定:
- `win_rate_b >= 0.55`（閾値は `PROMOTE_THRESHOLD` で調整可能）

手動判定では以下も参考:
- `avg_rank_b < avg_rank_a`
- `estimated_elo_b > 0`

## Makefile 主要パラメータ

| パラメータ | デフォルト | 説明 |
|:---|:---:|:---|
| `SELFPLAY_SHARDS` | 2 | 並列shard数 |
| `SELFPLAY_GAMES_PER_SHARD` | 10000 | shard あたり対局数 |
| `SELFPLAY_SIMULATIONS` | 256 | MCTS シミュレーション数 |
| `SELFPLAY_TEMPERATURE_DROP` | 20 | 序盤N手の探索温度=1.0 |
| `TRAIN_ARCHITECTURE` | mlp | モデル種別 (linear/mlp/cnn) |
| `TRAIN_EPOCHS` | 20 | MLP/CNNエポック数 |
| `TRAIN_LR` | 0.001 | MLP/CNN学習率 |
| `TRAIN_AUGMENT` | true | 8倍対称性データ拡張 |
| `TRAIN_CUMULATIVE_WINDOW` | 3 | 累積データの過去サイクル数 |
| `EVAL_GAMES` | 3000 | 評価対局数 |
| `PROMOTE_THRESHOLD` | 0.55 | 自動プロモート勝率閾値 |

## 忘れ防止チェックリスト

- [ ] `selfplay` の `metadata.json` を保存した
- [ ] `train` で使った `--data`, `--architecture`, `--augment` を記録した
- [ ] `eval` レポートを `Reports/` に保存した
- [ ] 昇格判定を満たしたモデルだけ `Models/model-best.json` に昇格した
- [ ] `export` で配布バンドルを生成した
- [ ] CoreML変換手順を `COREML_GUIDE.md` に従って実施した
