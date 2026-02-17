# CoreML 利用ガイド

最終更新: 2026-02-18

## 位置づけ

- `TrainerCLI export` は、学習済みモデルを推論向けに量子化した JSON バンドルとして出力します。
- 現状の出力は `inference_model.json` / `manifest.json` で、**直接 `.mlmodel` ではありません**。
- CoreML 変換はこの JSON を元に別工程で行います（本ドキュメントで手順を固定化）。

## 1. 書き出し（必須）

```bash
./.build/release/TrainerCLI export \
  --model Models/model-20260218-a.json \
  --output Exports/export-20260218-a
```

生成物:

- `Exports/export-20260218-a/inference_model.json`
- `Exports/export-20260218-a/manifest.json`

## 2. CoreML 変換（運用手順）

### 推奨方針

- iPhoneで使う最終形式は `mlmodel` または `mlpackage`。
- 変換は Mac mini 上で実施し、アプリには変換済みモデルだけを入れる。

### 変換ワークフロー（固定）

1. `inference_model.json` を読み込み
2. 推論式（方策logit + 価値線形モデル）を CoreML 側に再構築
3. `coremltools` で `mlmodel` / `mlpackage` を生成
4. 必要なら `quantize`（INT8/FP16）
5. Xcode プロジェクトへ追加

## 3. iPhone アプリでの利用方法

1. モデルファイルをアプリバンドルに含める
2. アプリ起動時に `MLModel` をロード
3. `PolicyValuePredicting` 実装を CoreML 推論版に差し替える
4. 対局中はバッチ推論を優先し、推論回数を制御する

## 4. 推論時の必須チェック

- [ ] 推論入力特徴量の並び順が学習時と一致
- [ ] `actionKey` 生成規則が一致（`P|piece|variant|x|y` / `PASS`）
- [ ] 量子化スケール（scale）の適用ミスがない
- [ ] 端末上で `1手あたり時間` と `熱` を計測

## 5. 失敗しやすい点

- 学習側の `boardEncoding` と推論側のプレイヤーindex対応ズレ
- `export` したモデルと `manifest` の組み合わせ違い
- モデル更新時にアプリ側の入力テンソル定義を更新し忘れる

## 6. 運用ルール（忘れ防止）

- モデルを更新したら、必ず以下を同時にコミット/保管
  - `Models/model-*.json`
  - `Exports/export-*/manifest.json`
  - `Reports/eval-*.json`
- 実機に配るモデルは `eval` 通過モデルのみ。
