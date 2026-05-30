import Foundation

/// Records diagnostic lines for smoke and unit tests.
public final class CapturingDiagnostics: Diagnostics, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var lines: [String] = []

    public init() {}

    public func log(_ level: DiagnosticLevel, _ message: String) {
        lock.lock()
        lines.append(message)
        lock.unlock()
        print("[\(level.rawValue)] \(message)")
    }
}
