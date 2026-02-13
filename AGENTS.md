# Repository Guidelines

## リポジトリ概要
- このリポジトリは SwiftUI 製の iOS アプリ `Blokus` の Xcode プロジェクトです。
- 主要対象は `Blokus.xcodeproj`、実装は `Blokus/`、テストは `BlokusTests/`、設計資料は `docs/` に置かれます。
- 本番実装方針は `ARCHITECTURE.md`、進行管理は `IMPLEMENTATION_CHECKLIST.md` を参照してください。

## Project Structure & Module Organization
- `Blokus/`  
  - `Views/`: 画面(UI)  
  - `DataTypes/`: ドメインモデル  
  - `Computers/`: コンピュータAI関連  
  - `*.swift`: ゲーム進行・状態管理（`Store`、`Board` など）
- `BlokusTests/`: テストコード（`Swift Testing` 使用）
- `.github/workflows/ci.yml`: CI のテスト定義

## Build, Test, and Development Commands
- `xcodebuild build -project Blokus.xcodeproj -scheme Blokus -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'`  
  - アプリのビルド
- `xcodebuild test -project Blokus.xcodeproj -scheme BlokusTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'`  
  - ローカル/CI と同等のテスト実行
- `open Blokus.xcodeproj`  
  - Xcode でスキーム/シミュレータを確認して実行

## Coding Style & Naming Conventions
- Swift 標準スタイル（インデントは 2 スペース）を基本とし、型名は `PascalCase`、メソッド/変数は `camelCase` を採用。
- ファイル名は型名と一致させる（例: `GameState.swift`、`ComputerEasy.swift`）。
- `Player`/`Turn`/`Board` など UI とロジックの責務を意識して命名する。
- 新規ユーティリティは `Store` の直接参照を増やしすぎないようにし、既存の状態管理の流れに沿って追加する。

## Testing Guidelines
- テストフレームワーク: `Testing`（`import Testing`）。
- テストは `BlokusTests/` 配下に配置し、`@Test` と `#expect` を使う。
- 非同期テストでは `async` 関数＋`Task.sleep` で状態遷移を待つ既存スタイルに合わせる。
- 可能な限り既存の AI/判定・状態遷移を単体で検証し、UI 依存のテストは最小化する。

## Commit & Pull Request Guidelines
- 直近の履歴に合わせ、`feat: ...`、`fix: ...` などの Conventional な接頭辞を推奨。`wip:` は作業中コミットに限定。
- PR には以下を必ず記載する:  
  1) 変更点の要約  
  2) 変更対象ファイル  
  3) 実行したテストコマンドと結果
- AI・ゲーム状態の仕様変更は、関連するテスト追加/更新を必須とし、画面変更がある場合はスクリーンショットか手順を添付する。

## Security & Environment Notes
- `info.plist` / `*.entitlements` の変更は最小限にし、外部 API キーや機密情報をコミットしない。
- `xcodebuild` の Simulator 名や OS バージョンは環境差で失敗しやすいので、必要に応じてローカルの利用可能なシミュレータ名へ置換する。
