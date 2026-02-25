import Domain
import Foundation

public enum BoardFeatureExtractor {
  public static let featureCount = 21

  public static func extract(
    boardEncoding: [UInt8],
    activePlayerIndex: Int,
    playerCount: Int = 4
  ) -> [Double] {
    let size = BoardConstants.boardSize
    let totalCells = Double(BoardConstants.boardCellCount)

    var cellCounts = Array(repeating: 0, count: playerCount)
    var anchorCounts = Array(repeating: 0, count: playerCount)
    var edgeCounts = Array(repeating: 0, count: playerCount)
    var comX = Array(repeating: 0.0, count: playerCount)
    var comY = Array(repeating: 0.0, count: playerCount)

    var edgeOfOwned = Array(repeating: Array(repeating: false, count: size * size), count: playerCount)
    var anchorSeen = Array(repeating: Array(repeating: false, count: size * size), count: playerCount)

    for idx in 0..<boardEncoding.count {
      let raw = boardEncoding[idx]
      guard raw > 0 else { continue }
      let p = Int(raw) - 1
      guard p < playerCount else { continue }
      cellCounts[p] += 1
      let px = idx % size
      let py = idx / size
      comX[p] += Double(px)
      comY[p] += Double(py)

      if px > 0 { edgeOfOwned[p][idx - 1] = true }
      if px < size - 1 { edgeOfOwned[p][idx + 1] = true }
      if py > 0 { edgeOfOwned[p][idx - size] = true }
      if py < size - 1 { edgeOfOwned[p][idx + size] = true }
    }

    for idx in 0..<boardEncoding.count {
      let raw = boardEncoding[idx]
      guard raw > 0 else { continue }
      let p = Int(raw) - 1
      guard p < playerCount else { continue }
      let px = idx % size
      let py = idx / size
      let diags = [(px - 1, py - 1), (px + 1, py - 1), (px - 1, py + 1), (px + 1, py + 1)]
      for (dx, dy) in diags {
        guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
        let di = dy * size + dx
        if boardEncoding[di] == 0, !edgeOfOwned[p][di], !anchorSeen[p][di] {
          anchorSeen[p][di] = true
          anchorCounts[p] += 1
        }
      }
    }

    for p in 0..<playerCount {
      for idx in 0..<(size * size) {
        if edgeOfOwned[p][idx], boardEncoding[idx] == 0 {
          edgeCounts[p] += 1
        }
      }
    }

    let center = Double(size - 1) / 2.0

    func relativeIndex(_ base: Int, _ offset: Int) -> Int {
      ((base + offset - activePlayerIndex) % playerCount + playerCount) % playerCount
    }

    var features = Array(repeating: 0.0, count: featureCount)
    var idx = 0

    for offset in 0..<playerCount {
      let p = (activePlayerIndex + offset) % playerCount
      features[idx] = Double(cellCounts[p]) / totalCells; idx += 1
      features[idx] = Double(anchorCounts[p]) / totalCells; idx += 1
      features[idx] = Double(edgeCounts[p]) / totalCells; idx += 1
    }

    let activeCells = Double(cellCounts[activePlayerIndex])
    let totalFilled = Double(cellCounts.reduce(0, +))
    let meanCells = totalFilled / Double(max(1, playerCount))
    let opponentCells = (0..<playerCount).filter { $0 != activePlayerIndex }.map { Double(cellCounts[$0]) }
    let bestOpponent = opponentCells.max() ?? 0

    features[idx] = (activeCells - meanCells) / totalCells; idx += 1
    features[idx] = (activeCells - bestOpponent) / totalCells; idx += 1
    features[idx] = totalFilled / totalCells; idx += 1
    features[idx] = (totalFilled / totalCells) * (totalFilled / totalCells); idx += 1

    for offset in 0..<playerCount {
      let p = (activePlayerIndex + offset) % playerCount
      let count = Double(cellCounts[p])
      if count > 0 {
        let cx = comX[p] / count
        let cy = comY[p] / count
        let dist = sqrt((cx - center) * (cx - center) + (cy - center) * (cy - center))
        features[idx] = dist / (center * sqrt(2))
      }
      idx += 1
    }

    features[idx] = Double(activePlayerIndex) / Double(max(1, playerCount - 1)); idx += 1

    return features
  }

  public static func extractFromGameState(
    _ state: GameState
  ) -> [Double] {
    let encoding = TrainingEncoding.encodeBoard(state)
    let activeIdx = state.turnOrder.firstIndex(of: state.activePlayerId) ?? 0
    return extract(
      boardEncoding: encoding,
      activePlayerIndex: activeIdx,
      playerCount: state.turnOrder.count
    )
  }

  public static func buildCNNInput(
    boardEncoding: [UInt8],
    activePlayerIndex: Int,
    playerCount: Int = 4
  ) -> [Double] {
    let spatialSize = BoardConstants.boardCellCount
    var channels = Array(repeating: 0.0, count: playerCount * spatialSize)

    for idx in 0..<boardEncoding.count {
      let raw = boardEncoding[idx]
      guard raw > 0 else { continue }
      let p = Int(raw) - 1
      guard p < playerCount else { continue }
      let channel = ((p - activePlayerIndex) % playerCount + playerCount) % playerCount
      channels[channel * spatialSize + idx] = 1.0
    }

    return channels
  }

  public static func buildCNNInputFromGameState(
    _ state: GameState
  ) -> [Double] {
    let encoding = TrainingEncoding.encodeBoard(state)
    let activeIdx = state.turnOrder.firstIndex(of: state.activePlayerId) ?? 0
    return buildCNNInput(
      boardEncoding: encoding,
      activePlayerIndex: activeIdx,
      playerCount: state.turnOrder.count
    )
  }
}
