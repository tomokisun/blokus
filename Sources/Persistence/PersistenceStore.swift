import Foundation
import SQLite3
import Domain

let sqliteTransient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class PersistenceStore {
  static let defaultTargetSchemaVersion = 1
  public static var targetSchemaVersion: Int {
    #if DEBUG
    return debugTargetSchemaVersionOverride ?? defaultTargetSchemaVersion
    #else
    return defaultTargetSchemaVersion
    #endif
  }

  #if DEBUG
  nonisolated(unsafe) public static var debugTargetSchemaVersionOverride: Int?
  public static func debugSetTargetSchemaVersion(_ version: Int?) {
    debugTargetSchemaVersionOverride = version
  }

  nonisolated(unsafe) public static var debugReadOnlyOpenError: StoreError?
  public static func debugSetReadOnlyOpenError(_ error: StoreError?) {
    debugReadOnlyOpenError = error
  }
  #endif

  var db: OpaquePointer?
  public private(set) var isReadOnly: Bool
  public private(set) var bootstrapError: StoreError?
  let decoder: JSONDecoder
  let encoder: JSONEncoder
  #if DEBUG
  public var debugSubmitAuditForceNilDetails = false
  public var debugExecuteStepResultOverride: Int32?
  public func debugSetBootstrapError(_ error: StoreError?) {
    bootstrapError = error
  }
  #endif

  public init(path: String, fallbackReadOnlyOnMigrationFailure: Bool = false) throws {
    self.isReadOnly = false
    self.bootstrapError = nil
    self.decoder = {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return decoder
    }()
    self.encoder = {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      return encoder
    }()

    var raw: OpaquePointer?
    if sqlite3_open_v2(
      path,
      &raw,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
      nil
    ) != SQLITE_OK {
      throw StoreError.openFailed("Cannot open database: \(path)")
    }
    db = raw

    do {
      try migrateSchema()
    } catch let error as StoreError {
      guard fallbackReadOnlyOnMigrationFailure else { throw error }
      sqlite3_close_v2(raw)
      db = nil
      bootstrapError = error
      isReadOnly = true
      #if DEBUG
      if let readOnlyError = Self.debugReadOnlyOpenError {
        Self.debugReadOnlyOpenError = nil
        throw readOnlyError
      }
      #endif

      if sqlite3_open_v2(
        path,
        &raw,
        SQLITE_OPEN_READONLY,
        nil
      ) != SQLITE_OK {
        throw error
      }
      db = raw
    } catch {
      throw error
    }
  }

  deinit {
    if let db { sqlite3_close_v2(db) }
  }

  // MARK: - SQLite Helpers

  func executeBatch(_ statements: [String]) throws {
    guard let db else { throw StoreError.openFailed("db closed") }
    for statement in statements {
      if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
        throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
      }
    }
  }

  func execute(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws {
    guard let db else { throw StoreError.openFailed("db closed") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind {
      bind(statement!)
    }
    #if DEBUG
    let rc = debugExecuteStepResultOverride ?? sqlite3_step(statement)
    #else
    let rc = sqlite3_step(statement)
    #endif
    if rc != SQLITE_DONE && rc != SQLITE_ROW {
      throw StoreError.executionFailed(String(cString: sqlite3_errmsg(db)))
    }
  }

  func query<T>(
    _ sql: String,
    bind: ((OpaquePointer) -> Void)? = nil,
    map: (OpaquePointer) throws -> T?
  ) throws -> [T] {
    guard let db else { throw StoreError.openFailed("db closed") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    if let bind { bind(statement!) }
    var rows: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let value = try map(statement!) {
        rows.append(value)
      }
    }
    return rows
  }

  func queryFirstColumn(
    sql: String,
    bind: ((OpaquePointer) -> Void)? = nil
  ) throws -> String? {
    let rows = try query(sql, bind: bind) { statement in
      if let c = sqlite3_column_text(statement, 0) {
        return String(cString: c)
      }
      return nil
    }
    return rows.first
  }

  func queryInt(_ sql: String, gameId: String) throws -> Int64 {
    let rows = try query(sql, bind: { statement in
      sqlite3_bind_text(statement, 1, gameId, -1, sqliteTransient)
    }) { statement in
      sqlite3_column_int64(statement, 0)
    }
    return rows.first ?? 0
  }

  func getNullableColumn<T>( _ statement: OpaquePointer, index: Int32) throws -> T? {
    if sqlite3_column_type(statement, index) == SQLITE_NULL {
      return nil
    }
    if T.self == String.self {
      guard let text = sqlite3_column_text(statement, index) else { return nil }
      return String(cString: text) as? T
    }
    return nil
  }

  #if DEBUG
  public func debugReadNullableInt(sql: String) throws -> Int? {
    let values = try query(sql, bind: nil) { statement in
      try getNullableColumn(statement, index: 0) as Int?
    }
    return values.first
  }
  #endif

  func userVersion() throws -> Int {
    let rows = try query("PRAGMA user_version;") { _ in } map: { statement in
      Int64(sqlite3_column_int64(statement, 0))
    }
    return Int(rows.first ?? 0)
  }

  func setUserVersion(_ version: Int) throws {
    try execute("PRAGMA user_version = \(version);")
  }

  func encodeDetails(_ values: [String: String]) -> String? {
    let sanitized = Dictionary(uniqueKeysWithValues: values.filter { !$0.value.isEmpty }.map { key, value in
      (key, value.trimmingCharacters(in: .whitespacesAndNewlines))
    })
    guard !sanitized.isEmpty else { return nil }
    guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: []) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
