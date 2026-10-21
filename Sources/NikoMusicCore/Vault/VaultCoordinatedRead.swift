import Foundation

/// One explicit restore read. Coordination gives the cloud client a chance to
/// materialize an ordinary zero-byte placeholder before manifest verification.
final class VaultCoordinatedRead: @unchecked Sendable {
    private let coordinator = NSFileCoordinator(filePresenter: nil)

    static func materialize(_ url: URL) async throws {
        let request = VaultCoordinatedRead()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                try await Task.detached(priority: .utility) {
                    try request.read(url)
                }.value
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
            try Task.checkCancellation()
        } onCancel: {
            request.coordinator.cancel()
        }
    }

    private func read(_ url: URL) throws {
        var coordinationError: NSError?
        var readError: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                _ = try handle.read(upToCount: 1)
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
    }
}
