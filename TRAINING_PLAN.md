# トレーニング計画（Blokus AI）

最終更新: 2026-02-18

## 目的

- M4 Mac mini で自己対戦データを継続生成し、`train -> eval -> export` を反復して強化する。
- iPhoneアプリ側は軽量推論（最終的に CoreML）に寄せる。

## 反復ループ

1. `selfplay` でデータ生成
2. `train` でモデル学習
3. `eval` で旧モデルと比較
4. 合格したモデルだけ `export`
5. iPhoneアプリへ統合して実機確認

## データ量の段階目標

1. 検証: 2,000局
2. ベースライン: 20,000局
3. 強化: 100,000局
4. 最強化: 300,000局+

## 推奨ディレクトリ運用

- 自己対戦: `TrainingRuns/<run-id>/`
- 学習モデル: `Models/model-<timestamp>.json`
- 評価結果: `Reports/eval-<timestamp>.json`
- 配布用: `Exports/export-<timestamp>/`

## 実行テンプレート

### 1) 自己対戦

```bash
./.build/release/TrainerCLI selfplay \
  --games 20000 \
  --players 4 \
  --simulations 320 \
  --max-candidates 56 \
  --parallel 8 \
  --output TrainingRuns/run-20260218-a
```

### 2) 学習

```bash
./.build/release/TrainerCLI train \
  --data TrainingRuns/run-20260218-a \
  --label model-20260218-a \
  --output Models/model-20260218-a.json
```

### 3) 評価

```bash
./.build/release/TrainerCLI eval \
  --model-a Models/model-20260218-prev.json \
  --model-b Models/model-20260218-a.json \
  --games 2000 \
  --players 4 \
  --simulations 160 \
  --parallel 8 \
  --output Reports/eval-20260218-a.json
```

### 4) 書き出し

```bash
./.build/release/TrainerCLI export \
  --model Models/model-20260218-a.json \
  --output Exports/export-20260218-a
```

## 昇格判定ルール（暫定）

- `eval` で以下を同時に満たしたら昇格候補
- `win_rate_b > 0.52`
- `avg_rank_b < avg_rank_a`
- `estimated_elo_b > estimated_elo_a`

## 忘れ防止チェックリスト

- [ ] `selfplay` の `metadata.json` を保存した
- [ ] `train` で使った `--data` と `--label` を記録した
- [ ] `eval` レポートを `Reports/` に保存した
- [ ] 昇格判定を満たしたモデルだけ `export` した
- [ ] CoreML変換手順を `COREML_GUIDE.md` に従って実施した
- [ ] iPhone実機で速度と消費電力を確認した
