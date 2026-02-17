## エラーログ

### 2026-02-18: GamePhase.swift に import Foundation 漏れ
- 原因: DomainTypes.swift 分割時に GamePhase.swift から `import Foundation` を付け忘れた
- 症状: `UUID` が見つからずコンパイルエラー（GameSubmitStatus の duplicate case で UUID を使用）
- 対処: `import Foundation` を追加して解決
- 教訓: 分割時は各ファイルに必要な import を確認すること
