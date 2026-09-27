import Foundation
@testable import NikoMusicCore

/// Hashes for real and counts every hash. Once armed, it cancels the running
/// Task after the first file below `root` and counts the hashes after that.
final class CancelOnHashHook: @unchecked Sendable {
    private let lock = NSLock()
    private let prefix: String
    private var armed = false
    private var didCancel = false
    private var afterCancel = 0
    private var total = 0

    init(below root: URL) {
        prefix = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    }

    var cancelled: Bool { lock.withLock { didCancel } }
    var hashesAfterCancel: Int { lock.withLock { afterCancel } }
    var hashedCount: Int { lock.withLock { total } }

    func arm() { lock.withLock { armed = true } }
    func disarm() { lock.withLock { armed = false } }

    func hash(_ url: URL) throws -> (byteCount: Int64, sha256: String) {
        let shouldCancel = lock.withLock { () -> Bool in
            total += 1
            guard armed, url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(prefix) else { return false }
            if didCancel {
                afterCancel += 1
                return false
            }
            didCancel = true
            return true
        }
        let result = try VaultManifestBuilder.hashRegularFile(at: url)
        if shouldCancel {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return result
    }
}
