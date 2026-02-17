## エラーログ

### 2026-02-18: GamePhase.swift に import Foundation 漏れ
- 原因: DomainTypes.swift 分割時に GamePhase.swift から `import Foundation` を付け忘れた
- 症状: `UUID` が見つからずコンパイルエラー（GameSubmitStatus の duplicate case で UUID を使用）
- 対処: `import Foundation` を追加して解決
- 教訓: 分割時は各ファイルに必要な import を確認すること

### 2026-02-18: queued ケースで古い state を返してしまうバグ
- 原因: CommandValidator.validate() の earlyReturn で返される status に含まれる state は検証時点のもの。GapManager.registerGap で self.state を更新しても、返り値の status 内の state は古いまま
- 症状: テストで queuedState.phase が .playing（期待値 .repair）、queuedState.eventGaps が空
- 対処: GapManager.registerGap 後に `.queued(state, queuedRange)` で更新済み state を返すように修正
- 教訓: サービス抽出時、earlyReturn のステータスに含まれる値オブジェクトが後続の処理で stale にならないか確認すること

## 2026-02-17T18:55:29.179Z
undefined

## 2026-02-17T19:16:48.618Z
undefined
