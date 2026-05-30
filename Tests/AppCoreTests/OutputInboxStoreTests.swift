import AppCore
import XCTest

final class OutputInboxStoreTests: XCTestCase {
    func testPersistsAddedItems() throws {
        let store = try makeStore()
        let fileURL = try makeExistingFile(named: "sample.wav")
        let item = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "dev-tool",
            status: .available,
            metadata: ["kind": "sample"]
        )

        try store.addItem(item)

        let items = try store.listItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fileURL, fileURL)
        XCTAssertEqual(items[0].metadata["kind"], "sample")
    }

    func testUpdatesExistingItem() throws {
        let store = try makeStore()
        var item = OutputInboxItem(
            fileURL: try makeExistingFile(named: "updated.wav"),
            sourceToolID: "dev-tool",
            status: .pending
        )

        try store.addItem(item)
        item.status = .available
        item.metadata = ["note": "ready"]
        try store.updateItem(item)

        let updated = try XCTUnwrap(store.listItems().first)
        XCTAssertEqual(updated.status, .available)
        XCTAssertEqual(updated.metadata["note"], "ready")
    }

    func testMarksMissingFiles() throws {
        let store = try makeStore()
        let missingURL = temporaryDirectory().appendingPathComponent("missing.wav")
        let item = OutputInboxItem(
            fileURL: missingURL,
            sourceToolID: "dev-tool",
            status: .available
        )

        try store.addItem(item)
        try store.refreshAvailability()

        XCTAssertEqual(try store.listItems().first?.status, .missing)
    }

    func testRefreshAvailabilityDoesNotNotifyWhenItemsAreUnchanged() throws {
        let store = try makeStore()
        let item = OutputInboxItem(
            fileURL: try makeExistingFile(named: "stable.wav"),
            sourceToolID: "dev-tool",
            status: .available
        )
        try store.addItem(item)

        let notification = expectation(
            forNotification: .outputInboxDidChange,
            object: nil
        )
        notification.isInverted = true

        try store.refreshAvailability()

        wait(for: [notification], timeout: 0.1)
    }

    func testOutputInboxInspectorSourceContainsRevealAndDragHandoff() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift",
            encoding: .utf8
        )

        [
            "OutputHandoff.isRevealable",
            "OutputHandoff.dragFileURL",
            "NSItemProvider(contentsOf:",
            "Reveal in Finder",
            "sampleRate",
            "bitDepth",
            "channels",
            "converter"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing inspector handoff source: \($0)")
        }
    }

    private func makeStore() throws -> JSONOutputInboxStore {
        let storeURL = temporaryDirectory().appendingPathComponent("inbox.json")
        return JSONOutputInboxStore(storageURL: storeURL)
    }

    private func makeExistingFile(named name: String) throws -> URL {
        let url = temporaryDirectory().appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubTests")
            .appendingPathComponent(UUID().uuidString)
    }
}
