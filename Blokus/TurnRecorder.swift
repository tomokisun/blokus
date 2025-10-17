import Foundation

actor TurnRecorder {
  private var turns: [Turn] = []

  func currentIndexOf(owner: Player) -> Int {
    turns.filter { $0.owner == owner }.count
  }

  func recordPlaceAction(piece: Piece, at origin: Coordinate) {
    let index = currentIndexOf(owner: piece.owner)
    let action = TurnAction.place(piece: piece, at: origin)
    turns.append(Turn(index: index, action: action, owner: piece.owner))
  }

  func recordPassAction(owner: Player) {
    let index = currentIndexOf(owner: owner)
    turns.append(Turn(index: index, action: .pass, owner: owner))
  }

  func recordedTurns() -> [Turn] {
    turns
  }
}
