import Foundation

/// Records diagnostic lines for smoke and unit tests.
/// Intentionally capture-only: no stdout. The E2E/stdout contract lives in
/// `ArchiveSmokeCommands` / `BookmarkRelaunchProofCommands`, which the release
/// scripts grep; this type backs in-process assertions via `lines`.
public final class CapturingDiagnostics: Diagnostics, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var lines: [String] = []

    public init() {}

    public func log(_ level: DiagnosticLevel, _ message: String) {
        lock.lock()
        lines.append(message)
        lock.unlock()
    }
}
