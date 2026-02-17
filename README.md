# BlokusApp

BlokusApp は、Blokus の対戦を扱う Swift マルチターゲットパッケージです。  
ローカル対局を軸に、順序制御・再生・復旧・監査性を重視した設計になっています。

## 目次

- [概要](#概要)
- [フォルダ構成](#フォルダ構成)
- [主要依存と要件](#主要依存と要件)
- [クイックスタート](#クイックスタート)
- [モジュール構成](#モジュール構成)
- [ゲーム状態と主要API](#ゲーム状態と主要api)
- [例: Engine/Connector経由での操作](#例-engineconnector経由での操作)
- [永続化と運用](#永続化と運用)
- [テスト](#テスト)
- [設計情報](#設計情報)

## 概要

- 言語: Swift
- パッケージ形式: Swift Package Manager (Package.swift)
- 対応プラットフォーム:
  - iOS 26+
  - macOS 10.15+
- 盤面: 10x10
- プレイヤー数: 2〜4 人
- 主要イベント:
  - `pass`（合法手なし時のみ）
  - `place`（ピースの配置）

## フォルダ構成

- `Sources/Domain`: ドメインモデル、コマンド・イベント・ルール判定の共通型
- `Sources/Engine`: ゲームロジック、submit/replay/tick の本体
- `Sources/Persistence`: SQLite 永続化、再生・復元・監査ログ
- `Sources/Connector`: Engine と Persistence をまとめて使う実行インターフェース
- `Sources/UI`: SwiftUI 向けの運用可視化コンポーネント
- `Tests/BlokusAppTests`: テスト群
- `DESIGN.md`: 仕様拡張・運用要件・DoD（本番運用前提）

## 主要依存と要件

- Swift 6.2 (swift-tools-version: 6.2)
- Foundation
- SQLite3
- Swift Testing（テスト）

必要に応じて macOS 環境で `sqlite3` バインディングが利用可能であること。

## クイックスタート

1. パッケージを取得

```bash
swift build
```

2. ビルド確認

```bash
swift test
```

3. フォーマット

```bash
make format
```

## モジュール構成

このパッケージは 5 つのライブラリターゲットを公開しています。

- `Domain`
- `Engine`
- `Persistence`
- `Connector`
- `UI`

### 製品の役割

- `Domain`: `GameState`、`GameCommand`、`MoveEvent`、`GameSubmitStatus` などのドメイン型を定義
- `Engine`: ゲームロジック（提出、適用、再生、欠番(gap)/再試行状態の遷移）
- `Persistence`: SQLite DDL/API、ゲーム状態保存、イベント保存、復元プラン作成、監査ログ
- `Connector`: `OperationalConnector` による実務的な操作窓口
- `UI`: 運用状態を可視化する SwiftUI コンポーネント

## ゲーム状態と主要 API

### 代表的な型

- `GameState`: 現在局面、フェーズ、ハッシュ連鎖、シーケンス情報、ギャップ情報を保持
- `GameCommand`: `place`/`pass` の提出コマンド（`commandId` などを含む）
- `MoveEvent`: コミット済みイベント（ハッシュ連鎖付き）
- `GameSubmitStatus`:
  - `accepted`
  - `queued`
  - `duplicate`
  - `rejected`
  - `authorityMismatch`
- `EventGap`: 欠番領域の再試行・期限情報

### 進行フェーズ

`waiting` / `syncing` / `reconciling` / `repair` / `readOnly` / `playing` / `finished`

## 例: Engine/Connector 経由での操作

### Engine で直接扱う

```swift
import Domain
import Engine

var state = GameState(
  gameId: "GAME-001",
  players: ["A", "B", "C"],
  authorityId: "A"
)
let engine = GameEngine(state: state)

let command = GameCommand(
  commandId: UUID(),
  clientId: "A",
  expectedSeq: 0,
  playerId: "A",
  action: .pass,
  gameId: "GAME-001",
  schemaVersion: GameState.schemaVersion,
  rulesVersion: GameState.rulesVersion,
  pieceSetVersion: PieceLibrary.currentVersion,
  issuedAt: Date(),
  issuedNanos: 0,
  nonce: 1,
  authSig: "sig"
)

let result = engine.submit(command)
```

### Connector を通す

```swift
import Connector
import Domain
import Engine
import Persistence

let state = GameState(gameId: "GAME-001", players: ["A", "B"], authorityId: "A")
let connector = try OperationalConnector(
  path: "/tmp/blokus.sqlite3",
  initialState: state
)

_ = try connector.submit(command)
let metrics = try connector.operationalMetrics()
```

## 永続化と運用

- DB は SQLite を利用し、`games` / `events` / `inbox_events` / `event_gaps` / `orphan_events` / `schema_migrations` を管理
- 起動時に再生可能イベントを再構築し、必要時は `orphan` 扱いで切り出し
- `tick()` で gap の再試行と readOnly へ移行する復旧フローを進行
- `OperationalDashboard`（`UI`）で gap・fork・orphan の状況を表示

## テスト

```bash
swift test
```

テストには以下が含まれます。

- 主要ルールの単体検証（着手可否、合図、終了判定）
- 再生・連番欠番・署名不正・リプレイ
- DB 復元、監査ログ、readOnly・migration 例外経路

## 設計情報

仕様の詳細は `DESIGN.md` を参照してください。
- 署名 (`authSig`) や nonce/issuedAt の再送防止
- `coordinationSeq` と hash chain ベースの整合性
- 欠番・再取得・repair/readOnly 遷移の方針
- 製品リリース判断基準（Definition of Done）
