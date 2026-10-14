import AppCore
import XCTest

extension XCTestCase {
    /// Expects `.outputInboxDidChange` from the store at `storageURL` only.
    ///
    /// The whole suite shares one process and `NotificationCenter.default`. A store changed off
    /// the main thread posts later through `DispatchQueue.main.async`, so an earlier test's posts
    /// can still be queued when this test first spins the run loop. An expectation that matches
    /// any sender lets those stray posts fulfill it (or fulfill an inverted one).
    func expectOutputInboxChange(storageURL: URL) -> XCTestExpectation {
        let ownURL = storageURL.standardizedFileURL
        return expectation(forNotification: .outputInboxDidChange, object: nil) { notification in
            notification.outputInboxStorageURL == ownURL
        }
    }

    /// Delivers every `.outputInboxDidChange` post already queued on the main queue.
    ///
    /// Call it at the end of an async test whose stores changed off the main thread, so its posts
    /// reach the run loop now and not inside a later test. The main actor runs on the serial main
    /// queue, so this hop runs after every post enqueued before it.
    func drainQueuedOutputInboxPosts() async {
        await MainActor.run {}
    }
}
