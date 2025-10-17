import Foundation
import SwiftUI

/// `Store` は、ゲームの状態管理を行うクラスです。
/// プレイヤーやコマ(`Piece`)、ボード(`Board`)の状況を保持し、
/// ユーザーやコンピュータプレイヤーのアクションに応じて更新します。
@MainActor @Observable final class Store: AnyObject {
  
  // MARK: - Properties
  
  /// ハイライト表示の有無を制御します。`true`の場合、配置可能箇所などをハイライトします。
  let isHighlight: Bool
  
  /// コンピュータ対戦モードの有無を示します。`true`の場合、コンピュータプレイヤーがゲームに参加します。
  let computerMode: Bool
  
  /// コンピュータプレイヤーの思考レベルを指定します。
  let computerLevel: ComputerLevel
  
  /// ボードの状態を保持するモデルです。
  var board = Board()
  
  /// ゲーム内で利用可能な全てのコマの配列です。
  var pieces = Piece.allPieces
  
  /// コンピュータプレイヤーのインスタンスを保持する配列です。
  var computerPlayers: [Computer]

  /// ターンの進行を管理します。
  private var turnManager = TurnManager()

  /// 現在ターンのプレイヤーの色を示します。
  private(set) var player = Player.red

  /// ゲームが終了したかどうかを示します。
  private(set) var isGameOver = false
  
  let trunRecorder = TrunRecorder()
  
  /// 現在選択されているコマ。`nil`の場合は未選択です。
  var pieceSelection: Piece?
  
  /// コンピュータプレイヤーが思考中かどうか、もしくは誰が思考中かを示します。
  var thinkingState = ComputerThinkingState.idle
  
  /// 現在ターンのプレイヤーが所有するコマの配列を取得します。
  var playerPieces: [Piece] {
    guard !isGameOver else { return [] }
    return pieces.filter { $0.owner == player }
  }
  
  // MARK: - Initializer
  
  /// `Store` の初期化を行います。
  ///
  /// - Parameters:
  ///   - isHighlight: ハイライト表示を行うかどうか。
  ///   - computerMode: コンピュータ対戦モードを有効にするかどうか。
  ///   - computerLevel: コンピュータプレイヤーの思考レベル。
  init(
    isHighlight: Bool,
    computerMode: Bool,
    computerLevel: ComputerLevel
  ) {
    self.isHighlight = isHighlight
    self.computerMode = computerMode
    self.computerLevel = computerLevel

    self.computerPlayers = [
      computerLevel.makeComputer(for: .blue),
      computerLevel.makeComputer(for: .green),
      computerLevel.makeComputer(for: .yellow)
    ]
  }
  
  // MARK: - Piece Operations
  
  /// 選択中の全てのコマを90度回転します。
  /// 回転は `piece.orientation` を更新することで実現します。
  func rotatePiece() {
    withAnimation(.default) {
      pieces = pieces.map {
        var piece = $0
        piece.orientation.rotate90()
        return piece
      }
    }
  }
  
  /// 選択中の全てのコマを反転します(上下反転)。
  /// 反転は `piece.orientation.flip()` を利用して行われます。
  func flipPiece() {
    withAnimation(.default) {
      pieces = pieces.map {
        var piece = $0
        piece.orientation.flip()
        return piece
      }
    }
  }

  /// `isHighlight` が有効な場合、現在選択されているコマが配置可能な箇所をボード上でハイライトします。
  /// 選択コマが無い場合はハイライトをクリアします。
  func updateBoardHighlights() {
    guard isHighlight else { return }
    if let piece = pieceSelection, piece.owner == player {
      board.highlightPossiblePlacements(for: piece)
    } else {
      board.clearHighlights()
    }
  }
  
  // MARK: - Player Actions
  
  /// プレイヤーが選択中のコマを指定した座標(`origin`)へ配置します。
  ///
  /// - Parameter origin: コマを配置するボード上の座標。
  /// - Note: 配置後は該当のコマを `pieces` から削除し、ハイライトを更新します。
  ///         配置が完了するとコンピュータプレイヤーの手番処理へ移行します。
  func cellButtonTapped(at origin: Coordinate) {
    guard !isGameOver else { return }
    guard let piece = pieceSelection, piece.owner == player else { return }
    let currentPlayer = player
    do {
      try board.placePiece(piece: piece, at: origin)

      withAnimation {
        pieceSelection = nil
        updateBoardHighlights()
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
          pieces.remove(at: index)
        }
      } completion: {
        Task(priority: .userInitiated) {
          await self.trunRecorder.recordPlaceAction(piece: piece, at: origin)
          let hasRemainingPieces = self.pieces.contains { $0.owner == currentPlayer }
          await self.finishTurn(with: .placed(player: currentPlayer, hasRemainingPieces: hasRemainingPieces))
        }
      }
    } catch {
      print(error)
    }
  }

  func passButtonTapped() {
    guard !isGameOver else { return }
    let currentPlayer = player
    Task(priority: .userInitiated) {
      await trunRecorder.recordPassAction(owner: currentPlayer)
      await finishTurn(with: .passed(player: currentPlayer))
    }
  }

  // MARK: - Turn Management

  private func finishTurn(with outcome: TurnOutcome) async {
    turnManager.advance(after: outcome)
    updateCurrentPlayerState()
    await continueAutomatedTurns()
  }

  private func continueAutomatedTurns() async {
    guard computerMode else { return }

    while let current = turnManager.currentPlayer,
          let computer = await computer(for: current) {
      pieceSelection = nil
      player = current
      updateBoardHighlights()

      do {
        thinkingState = .thinking(current)
        let outcome = try await performComputerTurn(computer)
        thinkingState = .idle
        turnManager.advance(after: outcome)
        updateCurrentPlayerState()
      } catch {
        thinkingState = .idle
        print(error)
        break
      }
    }
  }

  private func performComputerTurn(_ computer: Computer) async throws(PlacementError) -> TurnOutcome {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      await trunRecorder.recordPlaceAction(piece: candidate.piece, at: candidate.origin)

      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }

      let hasRemainingPieces = pieces.contains { $0.owner == candidate.piece.owner }
      return .placed(player: candidate.piece.owner, hasRemainingPieces: hasRemainingPieces)
    } else {
      let owner = await computer.owner
      await trunRecorder.recordPassAction(owner: owner)
      return .passed(player: owner)
    }
  }

  private func computer(for owner: Player) async -> Computer? {
    for computer in computerPlayers {
      if await computer.owner == owner {
        return computer
      }
    }
    return nil
  }

  private func updateCurrentPlayerState() {
    if let next = turnManager.currentPlayer {
      if player != next {
        player = next
      }
      pieceSelection = nil
      isGameOver = false
      updateBoardHighlights()
    } else {
      isGameOver = true
      pieceSelection = nil
      board.clearHighlights()
    }
  }
}

