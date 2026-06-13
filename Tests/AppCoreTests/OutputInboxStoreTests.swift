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

    func testAddItemDedupesByStandardizedFileURLAndSourceTool() throws {
        let store = try makeStore()
        let fileURL = try makeExistingFile(named: "dupe.wav")
        let alternateURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("subfolder")
            .appendingPathComponent("..")
            .appendingPathComponent(fileURL.lastPathComponent)
        let first = OutputInboxItem(
            fileURL: fileURL,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .pending,
            metadata: ["version": "first"]
        )
        let second = OutputInboxItem(
            fileURL: alternateURL,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 200),
            status: .available,
            metadata: ["version": "second"]
        )

        try store.addItem(first)
        try store.addItem(second)

        var items = try store.listItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, first.id)
        XCTAssertEqual(items[0].createdAt, first.createdAt)
        XCTAssertEqual(items[0].fileURL.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(items[0].status, .available)
        XCTAssertEqual(items[0].metadata["version"], "second")

        let otherTool = OutputInboxItem(
            fileURL: alternateURL,
            sourceToolID: "other-tool",
            status: .available
        )
        try store.addItem(otherTool)

        items = try store.listItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.sourceToolID.rawValue)), ["dev-tool", "other-tool"])
    }

    func testNewestItemsAppearFirst() throws {
        let store = try makeStore()
        let older = OutputInboxItem(
            fileURL: try makeExistingFile(named: "older.wav"),
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .available
        )
        let newer = OutputInboxItem(
            fileURL: try makeExistingFile(named: "newer.wav"),
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 200),
            status: .available
        )

        try store.addItem(older)
        try store.addItem(newer)

        let items = try store.listItems()
        XCTAssertEqual(items.map(\.fileURL.lastPathComponent), ["newer.wav", "older.wav"])
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

    func testCorruptInboxJSONThrows() throws {
        let storeURL = temporaryDirectory().appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not-json".utf8).write(to: storeURL)
        let store = JSONOutputInboxStore(storageURL: storeURL)

        XCTAssertThrowsError(try store.listItems())
    }

    func testOutputInboxInspectorSurfacesLoadErrors() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("inboxError"))
        XCTAssertTrue(source.contains("settingsError"))
        XCTAssertFalse(source.contains("(try? context.outputInboxStore.listItems()) ?? []"))
        XCTAssertFalse(source.contains("try? context.outputInboxStore.refreshAvailability()"))
    }

    func testRefreshAvailabilityTreatsDirectoriesAsMissing() throws {
        let store = try makeStore()
        let directoryURL = temporaryDirectory().appendingPathComponent("not-a-file.wav", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let item = OutputInboxItem(
            fileURL: directoryURL,
            sourceToolID: "dev-tool",
            status: .available
        )

        try store.addItem(item)
        try store.refreshAvailability()

        XCTAssertEqual(try store.listItems().first?.status, .missing)
    }

    func testConcurrentAddsPreserveEveryItem() async throws {
        let store = try makeStore()
        let baseDirectory = temporaryDirectory()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let item = OutputInboxItem(
                        fileURL: baseDirectory.appendingPathComponent("item-\(index).wav"),
                        sourceToolID: "stress",
                        status: .available,
                        metadata: ["index": "\(index)"]
                    )
                    try store.addItem(item)
                }
            }
            try await group.waitForAll()
        }

        let indexes = try store.listItems().compactMap { $0.metadata["index"] }.sorted()
        XCTAssertEqual(indexes.count, 40)
        XCTAssertEqual(Set(indexes).count, 40)
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
            "contextMenu",
            ".onDrag",
            "contentShape",
            "Drag the file to your DAW or Finder",
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing inspector handoff source: \($0)")
        }

        for removedNoise in ["sampleRate", "bitDepth", "channels", "Drag WAV", "item.status.rawValue.capitalized"] {
            XCTAssertFalse(
                source.contains(removedNoise),
                "Inspector should not show noisy chrome: \(removedNoise)"
            )
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
