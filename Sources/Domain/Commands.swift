import Foundation

public enum CommandAction: Codable, Hashable, Sendable {
  case place(pieceId: String, variantId: Int, origin: BoardPoint)
  case pass
}

public struct GameCommand: Codable, Hashable, Sendable {
  public var commandId: UUID
  public var clientId: String
  public var expectedSeq: Int
  public var playerId: PlayerID
  public var action: CommandAction
  public var gameId: GameID
  public var schemaVersion: Int
  public var rulesVersion: Int
  public var pieceSetVersion: Int
  public var issuedAt: Date
  public var issuedNanos: Int64
  public var nonce: Int64
  public var authSig: String

  public init(
    commandId: UUID = UUID(),
    clientId: String,
    expectedSeq: Int,
    playerId: PlayerID,
    action: CommandAction,
    gameId: GameID,
    schemaVersion: Int,
    rulesVersion: Int,
    pieceSetVersion: Int,
    issuedAt: Date,
    issuedNanos: Int64,
    nonce: Int64,
    authSig: String
  ) {
    self.commandId = commandId
    self.clientId = clientId
    self.expectedSeq = expectedSeq
    self.playerId = playerId
    self.action = action
    self.gameId = gameId
    self.schemaVersion = schemaVersion
    self.rulesVersion = rulesVersion
    self.pieceSetVersion = pieceSetVersion
    self.issuedAt = issuedAt
    self.issuedNanos = issuedNanos
    self.nonce = nonce
    self.authSig = authSig
  }

  public var commandFingerprintV4: Data {
    commandFingerprintMaterial().sha256()
  }

  public func commandFingerprintMaterial() -> Data {
    var writer = CanonicalWriter()
    writer.appendUInt32(UInt32(gameId.utf8.count))
    writer.appendString(gameId)
    writer.appendUInt32(UInt32(schemaVersion))
    writer.appendUInt32(UInt32(rulesVersion))
    writer.appendUInt32(UInt32(pieceSetVersion))
    writer.appendUInt32(UInt32(playerId.rawValue.utf8.count))
    writer.appendString(playerId.rawValue)
    switch action {
    case let .place(pieceId: pieceId, variantId: variantId, origin: origin):
      writer.appendUInt8(1)
      writer.appendUInt32(UInt32(pieceId.utf8.count))
      writer.appendString(pieceId)
      writer.appendUInt32(UInt32(variantId))
      writer.appendInt32(Int32(origin.x))
      writer.appendInt32(Int32(origin.y))
    case .pass:
      writer.appendUInt8(2)
    }
    writer.appendUInt32(UInt32(expectedSeq))
    writer.appendString(commandId.uuidString)
    return writer.data
  }
}
