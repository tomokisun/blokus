import Foundation

actor TrunRecorder {
  var truns: [Trun] = []
  
  func currentIndexOf(owner: Player) -> Int {
    truns.filter { $0.owner == owner }.count
  }
  
  func recordPlaceAction(piece: Piece, at origin: Coordinate) {
    let index = currentIndexOf(owner: piece.owner)
    let action = TrunAction.place(piece: piece, at: origin)
    truns.append(Trun(index: index, action: action, owner: piece.owner))
  }

  func recordPassAction(owner: Player) {
    let index = currentIndexOf(owner: owner)
    truns.append(Trun(index: index, action: .pass, owner: owner))
  }
}
