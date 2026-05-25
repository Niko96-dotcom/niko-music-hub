import XCTest
@testable import AppCore

final class OutputInboxNotificationTests: XCTestCase {
    func testAddItemPostsChangeNotification() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("inbox.json")
        let store = JSONOutputInboxStore(storageURL: storeURL)

        let expectation = expectation(forNotification: .outputInboxDidChange, object: nil)

        let item = OutputInboxItem(
            id: UUID(),
            fileURL: tempDir.appendingPathComponent("test.wav"),
            sourceToolID: ToolFeatureID("test"),
            createdAt: Date(),
            status: .available
        )
        try store.addItem(item)

        wait(for: [expectation], timeout: 1.0)
    }
}
