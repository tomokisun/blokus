## 完了タスク

### 2026-02-18: DomainTypes.swift を意味単位のファイルに分割

`Sources/Domain/DomainTypes.swift`（381 LOC, 20型）を以下の7ファイルに分割:
- `Player.swift` - PlayerID, GameID, Player
- `BoardPoint.swift` - BoardPoint
- `Piece.swift` - Piece, PieceVariantsCache, PieceLibrary
- `Commands.swift` - CommandAction, GameCommand
- `Events.swift` - MoveEventStatus, MoveEventSource, MoveEvent
- `GamePhase.swift` - GamePhase, SubmitRejectReason, GameSubmitStatus
- `Coordination.swift` - CoordinationAuthority, RepairContext, EventGap, StateHashChain, RecoveryResult

結果: ビルド成功、89テスト全パス。Public API 変更なし。
