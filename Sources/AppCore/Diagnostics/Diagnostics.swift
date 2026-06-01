import Foundation

public enum DiagnosticLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public protocol Diagnostics: Sendable {
    func log(_ level: DiagnosticLevel, _ message: String)
}

public struct ConsoleDiagnostics: Diagnostics {
    public init() {}

    public func log(_ level: DiagnosticLevel, _ message: String) {
        print("[\(level.rawValue)] \(message)")
    }
}
