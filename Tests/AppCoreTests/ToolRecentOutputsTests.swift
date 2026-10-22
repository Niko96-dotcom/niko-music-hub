import AppCore
import Combine
import XCTest

/// `ToolRecentOutputs` is the read side behind a tool page's list of its own
/// outputs. These tests prove the slice (tool, order, limit), the pass off the
/// main actor, coalesced requests, following the store, publishing only on
/// change, keeping the list on a failed read, and that a pass never writes or
/// takes the Output Inbox panel's corruption warning.
@MainActor
final class ToolRecentOutputsTests: XCTestCase {
    private let toolID: ToolFeatureID = "audio-recorder"

    // MARK: - Slice

    func testSliceKeepsOnlyTheToolsRowsNewestFirstWithinTheLimit() async {
        let rows = [
            row("take-1", createdAt: 100),
            row("take-3", createdAt: 300),
            row("other", tool: "wav-converter", createdAt: 400),
            row("take-2", createdAt: 200),
        ]
        let store = GatedListStore(rows: rows)

        let limited = ToolRecentOutputs(store: store, toolID: toolID, limit: 2)
        limited.refresh()
        await limited.waitForIdle()
        XCTAssertEqual(names(limited.items), ["take-3", "take-2"])

        let unlimited = ToolRecentOutputs(store: store, toolID: toolID)
        unlimited.refresh()
        await unlimited.waitForIdle()
        XCTAssertEqual(names(unlimited.items), ["take-3", "take-2", "take-1"])

        XCTAssertEqual(store.writeOrRefreshCalls, 0, "a pass must never write or refresh availability")
    }

    // MARK: - Off the main actor

    func testPassRunsOffTheMainActor() async {
        let entered = expectation(description: "first pass entered the store")
        let store = GatedListStore(rows: [row("take", createdAt: 100)], holdFirstList: true, firstListEntered: entered)
        let model = ToolRecentOutputs(store: store, toolID: toolID)

        model.refresh()
        await fulfillment(of: [entered], timeout: 5)

        // The pass is held inside the store, and this test still runs on the
        // main actor: the read does not block it.
        XCTAssertTrue(model.items.isEmpty)

        store.releaseFirstList()
        await model.waitForIdle()
        XCTAssertEqual(names(model.items), ["take"])
        XCTAssertEqual(store.firstListRanOnMainThread, false, "the store read must run off the main actor")
    }

    // MARK: - Coalescing

    func testRequestsDuringAPassCoalesceIntoOneFollowUpPass() async {
        // Posts that earlier tests queued on the main queue would start extra
        // passes of this model. A hop back from off the main actor runs after them.
        await Task.detached { await MainActor.run {} }.value
        let entered = expectation(description: "first pass entered the store")
        let store = GatedListStore(rows: [row("first", createdAt: 100)], holdFirstList: true, firstListEntered: entered)
        let model = ToolRecentOutputs(store: store, toolID: toolID)

        model.refresh()
        await fulfillment(of: [entered], timeout: 5)

        // A row written while the first pass is held must reach the list, and
        // the three requests must collapse into one follow-up pass.
        store.setRows([row("first", createdAt: 100), row("second", createdAt: 200)])
        model.refresh()
        model.refresh()
        model.refresh()

        store.releaseFirstList()
        await model.waitForIdle()

        XCTAssertEqual(store.listCalls, 2, "3 requests must collapse into 2 passes, never 1 (lost) nor 4")
        XCTAssertEqual(names(model.items), ["second", "first"])
    }

    // MARK: - Following the store

    func testFollowsTheStoresChanges() async throws {
        let store = JSONOutputInboxStore(storageURL: temporaryDirectory().appendingPathComponent("inbox.json"))
        let model = ToolRecentOutputs(store: store, toolID: toolID)
        let take = row("take", createdAt: 100)

        let listed = expectation(description: "the new take is listed")
        let subscription = model.$items.sink { items in
            if items.contains(where: { $0.id == take.id }) { listed.fulfill() }
        }
        defer { subscription.cancel() }

        // No `refresh()`: the store's own change notification starts the pass.
        try store.addItem(take)
        await fulfillment(of: [listed], timeout: 5)
        XCTAssertEqual(names(model.items), ["take"])
    }

    // MARK: - Publishing

    func testUnchangedSliceDoesNotPublish() async {
        let take = row("take", createdAt: 100)
        let store = GatedListStore(rows: [take])
        let model = ToolRecentOutputs(store: store, toolID: toolID)
        model.refresh()
        await model.waitForIdle()

        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        store.setRows([take, row("other", tool: "wav-converter", createdAt: 200)])
        model.refresh()
        await model.waitForIdle()

        XCTAssertEqual(publishes, 0, "another tool's row must not re-render this tool's page")
        XCTAssertEqual(names(model.items), ["take"])
    }

    func testFailedPassKeepsTheList() async {
        let store = GatedListStore(rows: [row("take", createdAt: 100)])
        let model = ToolRecentOutputs(store: store, toolID: toolID)
        model.refresh()
        await model.waitForIdle()

        store.failListing()
        model.refresh()
        await model.waitForIdle()

        XCTAssertEqual(store.listCalls, 2)
        XCTAssertEqual(names(model.items), ["take"], "a failed read must keep the last list")
    }

    // MARK: - Read side only

    func testCorruptionWarningStaysForTheOutputInbox() async throws {
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: storage)
        let store = JSONOutputInboxStore(storageURL: storage)
        let model = ToolRecentOutputs(store: store, toolID: toolID)

        model.refresh()
        await model.waitForIdle()

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(store.lastQuarantineURL, "the read quarantines the corrupt file, as listItems() does today")
        XCTAssertNotNil(store.takeCorruptionWarning(), "the one-time warning is the Output Inbox panel's to show")
    }

    // MARK: - Helpers

    private func row(_ name: String, tool: ToolFeatureID? = nil, createdAt seconds: TimeInterval) -> OutputInboxItem {
        OutputInboxItem(
            fileURL: URL(fileURLWithPath: "/tmp/ToolRecentOutputsTests/\(name).wav"),
            sourceToolID: tool ?? toolID,
            createdAt: Date(timeIntervalSince1970: seconds),
            status: .available
        )
    }

    private func names(_ items: [OutputInboxItem]) -> [String] {
        items.map { $0.fileURL.deletingPathExtension().lastPathComponent }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolRecentOutputsTests")
            .appendingPathComponent(UUID().uuidString)
    }
}

/// In-memory `OutputInboxStore` whose `listItems()` can be held on its first
/// call, counted and made to fail. It also counts every call a read-side model
/// must never make: writes and availability refreshes.
private final class GatedListStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [OutputInboxItem]
    private var _listCalls = 0
    private var _firstListRanOnMainThread: Bool?
    private var _writeOrRefreshCalls = 0
    private var _failsListing = false
    private let gate = DispatchSemaphore(value: 0)
    private let holdFirstList: Bool
    private let firstListEntered: XCTestExpectation?

    init(rows: [OutputInboxItem], holdFirstList: Bool = false, firstListEntered: XCTestExpectation? = nil) {
        self.rows = rows
        self.holdFirstList = holdFirstList
        self.firstListEntered = firstListEntered
    }

    var listCalls: Int { lock.withLock { _listCalls } }
    var firstListRanOnMainThread: Bool? { lock.withLock { _firstListRanOnMainThread } }
    var writeOrRefreshCalls: Int { lock.withLock { _writeOrRefreshCalls } }

    func setRows(_ newRows: [OutputInboxItem]) {
        lock.withLock { rows = newRows }
    }

    func failListing() {
        lock.withLock { _failsListing = true }
    }

    func releaseFirstList() {
        gate.signal()
    }

    func listItems() throws -> [OutputInboxItem] {
        let (call, fails) = lock.withLock { () -> (Int, Bool) in
            _listCalls += 1
            if _firstListRanOnMainThread == nil {
                _firstListRanOnMainThread = Thread.isMainThread
            }
            return (_listCalls, _failsListing)
        }
        if call == 1 {
            firstListEntered?.fulfill()
            if holdFirstList { gate.wait() }
        }
        if fails { throw CocoaError(.fileReadNoPermission) }
        return lock.withLock { rows }
    }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock { _writeOrRefreshCalls += 1 }
    }

    func updateItem(_ item: OutputInboxItem) throws {
        lock.withLock { _writeOrRefreshCalls += 1 }
    }

    func refreshAvailability() throws {
        lock.withLock { _writeOrRefreshCalls += 1 }
    }

    func loadRefreshedItems() throws -> [OutputInboxItem] {
        lock.withLock {
            _writeOrRefreshCalls += 1
            return rows
        }
    }
}
