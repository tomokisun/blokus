import Foundation
import SwiftUI

/// `Store` は、ゲームの状態管理を行うクラスです。
/// プレイヤーやコマ(`Piece`)、ボード(`Board`)の状況を保持し、
/// ユーザーやコンピュータプレイヤーのアクションに応じて更新します。
@MainActor @Observable final class Store: AnyObject {

  // MARK: - Properties

  /// ハイライト表示の有無を制御します。`true`の場合、配置可能箇所などをハイライトします。
  let isHighlight: Bool

  /// ゲームセッションを管理するモデルです。
  let game: GameSession

  /// 現在選択されているコマ。`nil`の場合は未選択です。
  var pieceSelection: Piece?

  // MARK: - Convenience Accessors

  var computerMode: Bool { game.computerMode }

  var computerLevel: ComputerLevel { game.computerLevel }

  var board: Board {
    get { game.board }
    set { game.board = newValue }
  }

  var pieces: [Piece] {
    get { game.pieces }
    set { game.pieces = newValue }
  }

  var player: Player {
    get { game.player }
    set { game.player = newValue }
  }

  var trunRecorder: TrunRecorder { game.trunRecorder }

  var thinkingState: ComputerThinkingState {
    get { game.thinkingState }
    set { game.thinkingState = newValue }
  }

  /// 現在ターンのプレイヤーが所有するコマの配列を取得します。
  var playerPieces: [Piece] {
    game.playerPieces
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
    self.game = GameSession(computerMode: computerMode, computerLevel: computerLevel)
  }

  // MARK: - Piece Operations

  /// 選択中の全てのコマを90度回転します。
  /// 回転は `piece.orientation` を更新することで実現します。
  func rotatePiece() {
    withAnimation(.default) {
      game.rotatePieces()
    }
  }

  /// 選択中の全てのコマを反転します(上下反転)。
  /// 反転は `piece.orientation.flip()` を利用して行われます。
  func flipPiece() {
    withAnimation(.default) {
      game.flipPieces()
    }
  }

  /// `isHighlight` が有効な場合、現在選択されているコマが配置可能な箇所をボード上でハイライトします。
  /// 選択コマが無い場合はハイライトをクリアします。
  func updateBoardHighlights() {
    guard isHighlight else { return }
    game.updateHighlights(for: pieceSelection)
  }

  // MARK: - Player Actions

  /// プレイヤーが選択中のコマを指定した座標(`origin`)へ配置します。
  ///
  /// - Parameter origin: コマを配置するボード上の座標。
  /// - Note: 配置後は該当のコマを `pieces` から削除し、ハイライトを更新します。
  ///         配置が完了するとコンピュータプレイヤーの手番処理へ移行します。
  func cellButtonTapped(at origin: Coordinate) {
    guard let piece = pieceSelection else { return }
    do {
      try withAnimation(.default) {
        try game.placeHumanPiece(piece, at: origin)
        pieceSelection = nil
        updateBoardHighlights()
      } completion: {
        Task(priority: .userInitiated) {
          await self.game.finalizeHumanTurn(with: piece, at: origin)
        }
      }
    } catch {
      print(error)
    }
  }

  func passButtonTapped() {
    Task(priority: .userInitiated) {
      await game.recordPass(for: player)
    }
  }
}
