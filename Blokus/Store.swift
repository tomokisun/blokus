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

  private let turnOrder = Player.allCases

  /// 現在ターンのプレイヤーの色を示します。
  private(set) var player = Player.red
  
  let turnRecorder = TurnRecorder()
  
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
      computerLevel.makeComputer(for: .blue),
      computerLevel.makeComputer(for: .green),
      computerLevel.makeComputer(for: .yellow)
    ]
  }
  
  // MARK: - Piece Operations
  
  /// 選択中のコマを90度回転します。
  /// 回転は `piece.orientation` を更新することで実現します。
  func rotatePiece() {
    guard var selection = pieceSelection else { return }

    withAnimation(.default) {
      selection.orientation.rotate90()
      pieceSelection = selection

      if let index = pieces.firstIndex(where: { $0.id == selection.id }) {
        pieces[index] = selection
      }

      updateBoardHighlights()
    }
  }

  /// 選択中のコマを反転します(上下反転)。
  /// 反転は `piece.orientation.flip()` を利用して行われます。
  func flipPiece() {
    guard var selection = pieceSelection else { return }

    withAnimation(.default) {
      selection.orientation.flip()
      pieceSelection = selection

      if let index = pieces.firstIndex(where: { $0.id == selection.id }) {
        pieces[index] = selection
      }

      updateBoardHighlights()
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
  func cellButtonTapped(at origin: Coordinate) {
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
          await self.turnRecorder.recordPlaceAction(piece: piece, at: origin)
          await self.advanceTurn()
        }
      }
    } catch {
      print(error)
    }
  }

  func passButtonTapped() {
    let passingPlayer = player
    Task(priority: .userInitiated) {
      await turnRecorder.recordPassAction(owner: passingPlayer)
      await self.advanceTurn()
    }
  }

  /// 現在の手番を次のプレイヤーへ進めます。
  /// コンピュータモードの場合は、次のプレイヤーがコンピュータである限り連続して処理を行います。
  func advanceTurn() async {
    var currentPlayer = player

    while true {
      let nextPlayer = nextPlayer(after: currentPlayer)
      updateCurrentPlayer(to: nextPlayer)

      guard computerMode, let computer = await computerPlayer(for: nextPlayer) else {
        thinkingState = .idle
        return
      }

      do {
        thinkingState = .thinking(nextPlayer)
        try await moveComputerPlayer(computer, owner: nextPlayer)
      } catch {
        print(error)
      }

      thinkingState = .idle
      currentPlayer = nextPlayer
    }
  }

  // MARK: - Computer Actions

  /// 特定のコンピュータプレイヤーが最適手(`candidate`)を計算し、取得した場合はそのコマを配置します。
  ///
  /// - Parameter computer: 思考・手番を実行するコンピュータプレイヤー。
  /// - Throws: 配置できない場合などエラーが発生する可能性があります。
  private func moveComputerPlayer(_ computer: Computer, owner: Player) async throws(PlacementError) {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      await turnRecorder.recordPlaceAction(piece: candidate.piece, at: candidate.origin)

      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    } else {
      await turnRecorder.recordPassAction(owner: owner)
    }
  }

  private func nextPlayer(after player: Player) -> Player {
    guard let index = turnOrder.firstIndex(of: player) else { return player }
    let nextIndex = turnOrder.index(after: index)
    return turnOrder[nextIndex == turnOrder.endIndex ? turnOrder.startIndex : nextIndex]
  }

  private func updateCurrentPlayer(to newPlayer: Player) {
    withAnimation(.default) {
      player = newPlayer
      pieceSelection = nil
    }
    updateBoardHighlights()
  }

  private func computerPlayer(for owner: Player) async -> Computer? {
    for computer in computerPlayers {
      if await computer.owner == owner {
        return computer
      }
    }
    return nil
  }
}

