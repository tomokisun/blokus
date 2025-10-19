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
  
  /// ゲームの手番順序。
  private let turnOrder = Player.allCases

  /// 現在の手番を示すインデックス。
  private var currentTurnIndex = 0

  /// 現在ターンのプレイヤーの色を示します。
  private(set) var currentPlayer: Player
  
  let turnRecorder = TurnRecorder()
  
  /// 現在選択されているコマ。`nil`の場合は未選択です。
  var pieceSelection: Piece?
  
  /// コンピュータプレイヤーが思考中かどうか、もしくは誰が思考中かを示します。
  var thinkingState = ComputerThinkingState.idle
  
  /// 現在ターンのプレイヤーが所有するコマの配列を取得します。
  var playerPieces: [Piece] {
    pieces.filter { $0.owner == currentPlayer }
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

    if computerMode {
      self.computerPlayers = [
        computerLevel.makeComputer(for: .blue),
        computerLevel.makeComputer(for: .green),
        computerLevel.makeComputer(for: .yellow)
      ]
    } else {
      self.computerPlayers = []
    }

    self.currentPlayer = turnOrder[currentTurnIndex]

    prepareForNextTurn()
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
    guard piece.owner == currentPlayer else { return }

    Task(priority: .userInitiated) {
      await handlePlacement(of: piece, at: origin)
    }
  }

  @MainActor
  private func handlePlacement(of piece: Piece, at origin: Coordinate) async {
    do {
      try board.placePiece(piece: piece, at: origin)

      withAnimation {
        pieceSelection = nil
        updateBoardHighlights()
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
          pieces.remove(at: index)
        }
      }

      await turnRecorder.recordPlaceAction(piece: piece, at: origin)
      await completeTurn()
    } catch {
      print(error)
    }
  }

  func passButtonTapped() {
    Task(priority: .userInitiated) {
      await turnRecorder.recordPassAction(owner: currentPlayer)
      await completeTurn()
    }
  }

  /// 現在の手番を次のプレイヤーへ進めます。
  func advanceTurn() {
    guard !turnOrder.isEmpty else { return }

    currentTurnIndex = (currentTurnIndex + 1) % turnOrder.count
    currentPlayer = turnOrder[currentTurnIndex]
    prepareForNextTurn()
  }

  /// 全てのコンピュータプレイヤーが思考・配置する工程を順番に実行します。
  private func moveComputerPlayers() async {
    guard computerMode else { return }

    while let computer = await computer(for: currentPlayer) {
      do {
        thinkingState = .thinking(currentPlayer)
        try await moveComputerPlayer(computer)
      } catch {
        print(error)
      }

      thinkingState = .idle
      advanceTurn()
    }
  }

  /// 現在の手番が完了した後の共通処理を行います。
  private func completeTurn() async {
    advanceTurn()
    await moveComputerPlayers()
  }

  /// 手番開始時の共通状態を整えます。
  private func prepareForNextTurn() {
    pieceSelection = nil
    updateBoardHighlights()
  }

  /// 現在の手番プレイヤーに対応するコンピュータを取得します。
  private func computer(for player: Player) async -> Computer? {
    guard computerMode else { return nil }

    for computer in computerPlayers {
      let owner = await computer.owner
      if owner == player {
        return computer
      }
    }

    return nil
  }
  
  // MARK: - Computer Actions
  
  /// 特定のコンピュータプレイヤーが最適手(`candidate`)を計算し、取得した場合はそのコマを配置します。
  ///
  /// - Parameter computer: 思考・手番を実行するコンピュータプレイヤー。
  /// - Throws: 配置できない場合などエラーが発生する可能性があります。
  private func moveComputerPlayer(_ computer: Computer) async throws(PlacementError) {
    if let candidate = await computer.moveCandidate(board: board, pieces: pieces) {
      try board.placePiece(piece: candidate.piece, at: candidate.origin)
      await turnRecorder.recordPlaceAction(piece: candidate.piece, at: candidate.origin)
      
      withAnimation(.default) {
        if let index = pieces.firstIndex(where: { $0.id == candidate.piece.id }) {
          pieces.remove(at: index)
        }
      }
    } else {
      await turnRecorder.recordPassAction(owner: computer.owner)
    }
  }
}

