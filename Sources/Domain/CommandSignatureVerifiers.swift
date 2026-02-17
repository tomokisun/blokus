import Foundation
import CryptoKit

public protocol CommandSignatureVerifying: Sendable {
  func verify(_ command: GameCommand) -> Bool
}

public struct DefaultCommandSignatureVerifier: CommandSignatureVerifying {
  private let keysByPlayer: [PlayerID: String]
  public init(keysByPlayer: [PlayerID: String]) { self.keysByPlayer = keysByPlayer }

  public func verify(_ command: GameCommand) -> Bool {
    guard let key = keysByPlayer[command.playerId] else { return false }
    return DefaultCommandSignatureVerifier.signature(for: command, key: key) == command.authSig
  }

  public static func signature(for command: GameCommand, key: String) -> String {
    let payload = DefaultCommandSignatureVerifier.signaturePayload(command)
    let secret = SymmetricKey(data: Data(key.utf8))
    let signature = HMAC<SHA256>.authenticationCode(for: payload, using: secret)
    return Data(signature).hexString
  }

  private static func signaturePayload(_ command: GameCommand) -> Data {
    var writer = CanonicalWriter()
    writer.appendData(command.commandFingerprintV4)
    writer.appendInt64(command.issuedNanos)
    let issuedNanos = Int64(command.issuedAt.timeIntervalSince1970 * 1_000_000_000)
    writer.appendInt64(issuedNanos)
    writer.appendInt64(command.nonce)
    return writer.data
  }
}

public struct PermissiveCommandSignatureVerifier: CommandSignatureVerifying {
  public init() {}
  public func verify(_ command: GameCommand) -> Bool { true }
}
