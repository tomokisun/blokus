import Foundation
import CryptoKit

public struct CanonicalWriter {
  public private(set) var bytes: [UInt8] = []

  public init() {
    self.bytes = []
  }

  public mutating func appendUInt8(_ value: UInt8) {
    bytes.append(value)
  }

  public mutating func appendUInt16(_ value: UInt16) {
    bytes.append(UInt8((value >> 8) & 0xff))
    bytes.append(UInt8(value & 0xff))
  }

  public mutating func appendUInt32(_ value: UInt32) {
    appendUInt16(UInt16((value >> 16) & 0xffff))
    appendUInt16(UInt16(value & 0xffff))
  }

  public mutating func appendInt32(_ value: Int32) {
    appendUInt32(UInt32(bitPattern: value))
  }

  public mutating func appendInt64(_ value: Int64) {
    let (high, low) = value.uint32Pair
    appendUInt32(high)
    appendUInt32(low)
  }

  public mutating func appendString(_ value: String) {
    let utf8 = Array(value.utf8)
    appendUInt32(UInt32(utf8.count))
    bytes.append(contentsOf: utf8)
  }

  public mutating func appendData(_ data: Data) {
    appendUInt32(UInt32(data.count))
    bytes.append(contentsOf: data)
  }

  public var data: Data {
    Data(bytes)
  }
}

extension Collection where Index == Int {
  public subscript(safe index: Int) -> Element? {
    guard index >= startIndex && index < endIndex else { return nil }
    return self[index]
  }
}

extension Int64 {
  public var uint32Pair: (UInt32, UInt32) {
    let hi = UInt32((self >> 32) & 0xffff_ffff)
    let lo = UInt32(self & 0xffff_ffff)
    return (hi, lo)
  }
}

extension Data {
  public var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }

  public var hex: String {
    map { String(format: "%02x", $0) }.joined()
  }

  public func sha256() -> Data {
    Data(SHA256.hash(data: self))
  }
}
