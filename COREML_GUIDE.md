# CoreML 利用ガイド

最終更新: 2026-02-20

## 位置づけ

現在の iPhone 推論は **純 Swift 実装** (`LearnedPolicyValuePredictor`) で動作しており、
CoreML への変換は **不要** です。本ドキュメントは、将来 Neural Engine によるハードウェア
アクセラレーションが必要になった場合の変換手順を記載しています。

## 現在の推論パス（CoreML 不要）

```
Models/model-best.json
  → TrainedModelIO.load()
  → LearnedPolicyValuePredictor(model:)
  → 純 Swift で MLP/CNN 順伝播
```

- `LearnedPolicyValuePredictor` が `architecture` フィールドを見て自動で linear/mlp/cnn を切り替え
- MLP: `BoardFeatureExtractor` で 21 特徴量抽出 → `MLPInference.predict` で順伝播
- CNN: `BoardFeatureExtractor.buildCNNInput` で 20×20×4ch 構築 → `CNNInference.predict` で順伝播
- MCTS 内で毎手数百〜数千回呼ばれても MLP なら十分高速（数μs/回）

## export の役割

`TrainerCLI export` は、モデルを Int16 量子化した配布用 JSON バンドルとして出力します。

```bash
./.build/release/TrainerCLI export \
  --model Models/model-best.json \
  --output Exports/export-latest
```

生成物:
- `inference_model.json`: 量子化済み推論モデル（方策バイアス + 価値モデル重み）
- `manifest.json`: ソースモデルのハッシュ・ラベル・バージョン

`inference_model.json` には `architecture` フィールドがあり、モデル種別を識別:
- `"linear"`: 線形価値モデルのみ
- `"mlp"`: MLP 全層の量子化重み（`mlpValueModel`）を含む
- `"cnn"`: Conv2D + Dense 全層の量子化重み（`cnnValueModel`）を含む

## CoreML にすべきか？

### MLP（現在の推奨アーキテクチャ）→ CoreML 化は不要

現在の MLP は 21→64→32→1（約 3,400 回の乗算）と非常に小さい。

| | 純 Swift | CoreML |
|:---|:---|:---|
| 計算本体 | ~数μs | ~数μs |
| オーバーヘッド | なし | MLMultiArray 変換 + Neural Engine ディスパッチ |
| **合計** | **~数μs** | **~数十〜数百μs** |

CoreML はモデルが小さすぎると、計算よりデータの受け渡しコストが支配的になる。
MCTS で 1 手あたり数百〜数千回呼ばれる推論では、このオーバーヘッドが累積して
**純 Swift より遅くなる可能性が高い**。

**結論: MLP を使う限り、純 Swift 実装のままが最速。**

### CNN やより大きなモデル → CoreML 化を検討

CoreML が有利になる条件:
- 計算量が大きいモデル（数万〜数百万回の乗算、CNN など）
- バッチ推論（複数入力をまとめて処理）
- GPU / Neural Engine の並列性が活きるサイズ

将来 CNN や大規模 MLP に移行した場合は、CoreML 化で推論速度が改善する見込みがある。

## 参考: CoreML 変換手順

CNN など大きなモデルに移行し、Neural Engine による高速化が必要になった場合に実施。

### 変換ワークフロー

1. `inference_model.json` を読み込み、`architecture` フィールドを確認
2. アーキテクチャに応じた推論グラフを CoreML 側に再構築:
   - `linear`: 方策logit + 4特徴量線形回帰
   - `mlp`: 方策logit + 21特徴量 → Dense(64,ReLU) → Dense(32,ReLU) → Dense(1)
   - `cnn`: 方策logit + 20×20×4ch → Conv2D×2(ReLU) → GAP → Dense(32,ReLU) → Dense(1)
3. 量子化重みの復元: `dequantized = Int16(value) × scale`
4. `coremltools` で `mlmodel` / `mlpackage` を生成
5. 必要なら `quantize`（INT8/FP16）
6. Xcode プロジェクトへ追加

### iPhone アプリでの利用方法

1. モデルファイルをアプリバンドルに含める
2. アプリ起動時に `MLModel` をロード
3. `PolicyValuePredicting` 実装を CoreML 推論版に差し替える
4. 対局中はバッチ推論を優先し、推論回数を制御する

## 推論時の必須チェック（CoreML 変換時）

- [ ] `architecture` に応じた推論パスを使用
- [ ] MLP: `BoardFeatureExtractor` の21特徴量の並び順が学習時と一致
- [ ] CNN: 入力チャンネル順序（ch0=手番プレイヤー, ch1-3=他プレイヤー）が一致
- [ ] `actionKey` 生成規則が一致（`P|piece|variant|x|y` / `PASS`）
- [ ] 量子化スケール（scale）の適用ミスがない: `dequantized = Int16(value) × scale`
- [ ] 端末上で `1手あたり時間` と `熱` を計測

## 失敗しやすい点

- 学習側の `boardEncoding` と推論側のプレイヤーindex対応ズレ
- `export` したモデルと `manifest` の組み合わせ違い
- モデル更新時にアプリ側の入力テンソル定義を更新し忘れる

## 運用ルール

- モデルを更新したら、必ず以下を同時にコミット/保管
  - `Models/model-*.json`
  - `Exports/export-*/manifest.json`
  - `Reports/eval-*.json`
- 実機に配るモデルは `eval` 通過モデルのみ
