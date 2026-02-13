import Foundation
import Dependencies

enum AuditLevel: String, Sendable {
  case critical
  case event
  case debug
}

struct AuditEvent: Equatable, Sendable {
  let correlationId: String
  let level: AuditLevel
  let name: String
  let payload: String
  let timestamp: Date
}

protocol AuditLogger: Sendable {
  func log(_ event: AuditEvent)
}

struct NullAuditLogger: AuditLogger {
  func log(_ event: AuditEvent) {}
}

struct LiveAuditLogger: AuditLogger {
  func log(_ event: AuditEvent) {
    print("[\(event.level.rawValue)] \(event.timestamp): \(event.name) - \(event.payload)")
  }
}

enum AuditLoggerKey: TestDependencyKey {
  static var liveValue: any AuditLogger { LiveAuditLogger() }
  static var testValue: any AuditLogger { NullAuditLogger() }
  static var previewValue: any AuditLogger { LiveAuditLogger() }
}

extension DependencyValues {
  var auditLogger: any AuditLogger {
    get { self[AuditLoggerKey.self] }
    set { self[AuditLoggerKey.self] = newValue }
  }
}
