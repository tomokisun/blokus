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
  var computerPlayers: [ComputerPlayer]
  
  /// 現在ターンのプレイヤーの色を示します。
  var player = PlayerColor.red
  
  /// 現在選択されているコマ。`nil`の場合は未選択です。
  var pieceSelection: Piece?
  
  /// コンピュータプレイヤーが思考中かどうか、もしくは誰が思考中かを示します。
  var thinkingState = ComputerThinkingState.idle
  
  /// 現在ターンのプレイヤーが所有するコマの配列を取得します。
  var playerPieces: [Piece] {
    pieces.filter { $0.owner == player }
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
      ComputerPlayer(owner: .blue, level: computerLevel),
      ComputerPlayer(owner: .green, level: computerLevel),
      ComputerPlayer(owner: .yellow, level: computerLevel)
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
    if let piece = pieceSelection {
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
  func movePlayerPiece(at origin: Coordinate) {
    guard let piece = pieceSelection else { return }
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
          await self.moveComputerPlayers()
        }
      }
    } catch {
      print(error)
    }
  }
  
  /// 全てのコンピュータプレイヤーが思考・配置する工程を順番に実行します。
  private func moveComputerPlayers() async {
    for player in computerPlayers {
      do {
        thinkingState = .thinking(player.owner)
        try await moveComputerPlayer(player)
        thinkingState = .idle
      } catch {
        print(error)
        thinkingState = .idle
      }
    }
  }
  
  // MARK: - Computer Actions
  
  /// 特定のコンピュータプレイヤーが最適手(`candidate`)を計算し、取得した場合はそのコマを配置します。
  ///
  /// - Parameter computer: 思考・手番を実行するコンピュータプレイヤー。
  /// - Throws: 配置できない場合などエラーが発生する可能性があります。
  private func moveComputerPlayer(_ computer: ComputerPlayer) async throws(PlacementError) {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      
      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    }
  }
}

