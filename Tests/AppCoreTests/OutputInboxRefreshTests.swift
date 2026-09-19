import AppCore
import XCTest

/// Refresh-correction proofs for the Output Inbox.
///
/// The production path is `OutputInboxRefreshModel.requestRefresh()` (main
/// thread only enqueues) driving `JSONOutputInboxStore.loadRefreshedItems()`
/// (single load/scan/save/sort pass) on a background task. These tests prove:
/// main-thread responsiveness with a blocked store, burst coalescing without
/// a lost refresh, no lost concurrent updates, preserved identity/order,
/// surfaced (never masked) corruption with recovery, and no history cap.
final class OutputInboxRefreshTests: XCTestCase {
    // MARK: - Off-main-thread refresh with latest result

    @MainActor
    func testRefreshRunsOffMainThreadAndPublishesLatestSnapshot() async throws {
        let files = try (0..<5).map { try makeExistingFile(named: "offmain-\($0).wav") }
        let items = files.enumerated().map { index, url in
            OutputInboxItem(
                fileURL: url,
                sourceToolID: "dev-tool",
                createdAt: Date(timeIntervalSince1970: Double(100 + index)),
                status: .pending
            )
        }
        let store = GatedInboxStore(items: items, blockFirstPass: true)
        let model = OutputInboxRefreshModel(store: store)

        model.requestRefresh()
        XCTAssertTrue(model.isRefreshing, "request must be accepted without blocking")

        // The main actor must stay responsive while the store pass is blocked.
        let mainResponded = await MainActor.run { Thread.isMainThread }
        XCTAssertTrue(mainResponded, "main actor must run while a refresh pass is blocked")
        XCTAssertTrue(model.isRefreshing)
        XCTAssertNil(model.lastError)

        store.releaseFirstPass()
        await model.waitForIdle()

        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.items.count, 5)
        XCTAssertEqual(
            model.items.map(\.fileURL.lastPathComponent),
            (0..<5).reversed().map { "offmain-\($0).wav" },
            "newest first, latest refresh result published"
        )
        XCTAssertEqual(store.mainThreadObserved, false, "refresh I/O must run off the main actor")
    }

    // MARK: - Burst coalescing without a lost refresh

    @MainActor
    func testNotificationBurstsCoalesceIntoOneFollowUpPass() async throws {
        let first = OutputInboxItem(
            fileURL: temporaryDirectory().appendingPathComponent("first.wav"),
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .available
        )
        let store = GatedInboxStore(items: [first], blockFirstPass: true)
        let model = OutputInboxRefreshModel(store: store)

        model.requestRefresh()
        try await waitUntil("first pass enters the store") { store.loadCalls == 1 }

        // State written while the first pass is in-flight must be observed,
        // and the two extra requests must collapse into a single follow-up.
        let second = OutputInboxItem(
            fileURL: temporaryDirectory().appendingPathComponent("second.wav"),
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 200),
            status: .available
        )
        store.setItems([first, second])
        model.requestRefresh()
        model.requestRefresh()

        store.releaseFirstPass()
        await model.waitForIdle()

        XCTAssertEqual(store.loadCalls, 2, "3 requests must collapse into 2 passes, never 1 (lost) nor 3")
        XCTAssertEqual(
            model.items.map(\.fileURL.lastPathComponent),
            ["second.wav", "first.wav"],
            "follow-up pass must publish the state written during the in-flight pass"
        )
    }

    // MARK: - Concurrent updates are not overwritten

    func testConcurrentAddsDuringAvailabilityRefreshArePreserved() async throws {
        let store = try makeStore()
        let base = temporaryDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for index in 0..<10 {
            let url = base.appendingPathComponent("seed-\(index).wav")
            try Data("audio".utf8).write(to: url)
            try store.addItem(OutputInboxItem(
                fileURL: url,
                sourceToolID: "stress",
                status: .available,
                metadata: ["slot": "seed-\(index)"]
            ))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await Task.detached(priority: .utility) {
                    try store.loadRefreshedItems()
                }.value
            }
            for index in 0..<10 {
                group.addTask {
                    try await Task.detached(priority: .utility) {
                        try store.addItem(OutputInboxItem(
                            fileURL: base.appendingPathComponent("racy-\(index).wav"),
                            sourceToolID: "stress",
                            status: .available,
                            metadata: ["slot": "racy-\(index)"]
                        ))
                    }.value
                }
            }
            try await group.waitForAll()
        }

        let slots = try store.listItems().compactMap { $0.metadata["slot"] }
        XCTAssertEqual(slots.count, 20, "every concurrent add must survive the refresh save")
        XCTAssertEqual(Set(slots).count, 20)
    }

    // MARK: - Identity, order, error visibility, recovery, no cap

    func testLoadRefreshedItemsPreservesIdentityAndNewestFirstOrder() throws {
        let store = try makeStore()
        let existing = try makeExistingFile(named: "kept.wav")
        let missing = temporaryDirectory().appendingPathComponent("gone.wav")
        let kept = OutputInboxItem(
            fileURL: existing,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 300),
            status: .pending
        )
        let gone = OutputInboxItem(
            fileURL: missing,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 400),
            status: .available
        )
        try store.addItem(kept)
        try store.addItem(gone)

        let snapshot = try store.loadRefreshedItems()

        XCTAssertEqual(snapshot.map(\.fileURL.lastPathComponent), ["gone.wav", "kept.wav"])
        let byName = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.fileURL.lastPathComponent, $0) })
        XCTAssertEqual(byName["kept.wav"]?.id, kept.id, "availability flip must not re-identity the record")
        XCTAssertEqual(byName["kept.wav"]?.createdAt, kept.createdAt)
        XCTAssertEqual(byName["kept.wav"]?.status, .available, "existing pending file becomes available")
        XCTAssertEqual(byName["gone.wav"]?.id, gone.id)
        XCTAssertEqual(byName["gone.wav"]?.status, .missing)
    }

    func testLoadRefreshedItemsMatchesTwoStepRefresh() throws {
        let makePair = { () throws -> (JSONOutputInboxStore, URL) in
            let directory = self.temporaryDirectory()
            let storage = directory.appendingPathComponent("inbox.json")
            let file = directory.appendingPathComponent("track.wav")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("audio".utf8).write(to: file)
            let items = [
                OutputInboxItem(
                    fileURL: file,
                    sourceToolID: "dev-tool",
                    createdAt: Date(timeIntervalSince1970: 100),
                    status: .pending
                ),
                OutputInboxItem(
                    fileURL: directory.appendingPathComponent("absent.wav"),
                    sourceToolID: "dev-tool",
                    createdAt: Date(timeIntervalSince1970: 200),
                    status: .available
                ),
            ]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: storage, options: .atomic)
            return (JSONOutputInboxStore(storageURL: storage), storage)
        }

        let (single, sourceStorage) = try makePair()
        let secondStorage = sourceStorage.deletingLastPathComponent().appendingPathComponent("second-inbox.json")
        try FileManager.default.copyItem(at: sourceStorage, to: secondStorage)
        let twoStep = JSONOutputInboxStore(storageURL: secondStorage)
        let combined = try single.loadRefreshedItems()
        try twoStep.refreshAvailability()
        let sequential = try twoStep.listItems()

        XCTAssertEqual(combined, sequential, "single pass must equal refresh + list exactly")
    }

    func testLoadRefreshedItemsNotifiesOnlyWhenStatusesChange() throws {
        let store = try makeStore()
        try store.addItem(OutputInboxItem(
            fileURL: try makeExistingFile(named: "flip.wav"),
            sourceToolID: "dev-tool",
            status: .pending
        ))

        let changed = expectation(forNotification: .outputInboxDidChange, object: nil)
        _ = try store.loadRefreshedItems()
        wait(for: [changed], timeout: 2.0)

        let silent = expectation(forNotification: .outputInboxDidChange, object: nil)
        silent.isInverted = true
        _ = try store.loadRefreshedItems()
        wait(for: [silent], timeout: 0.2)
    }

    func testCorruptInboxJSONThrowsAndIsNeverMasked() throws {
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: storage)
        let store = JSONOutputInboxStore(storageURL: storage)

        XCTAssertThrowsError(try store.loadRefreshedItems(), "corruption must throw, not return []")
    }

    @MainActor
    func testModelSurfacesCorruptionThenRecovers() async throws {
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: storage)
        let store = JSONOutputInboxStore(storageURL: storage)
        let model = OutputInboxRefreshModel(store: store)

        model.requestRefresh()
        await model.waitForIdle()
        XCTAssertNotNil(model.lastError, "corruption must surface as a visible error")
        XCTAssertTrue(model.items.isEmpty)

        // Recovery is a plain retry from disk: no restart, no hidden reset.
        let file = directory.appendingPathComponent("back.wav")
        try Data("audio".utf8).write(to: file)
        let recovered = [OutputInboxItem(
            fileURL: file,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 50),
            status: .pending
        )]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(recovered).write(to: storage, options: .atomic)

        model.requestRefresh()
        await model.waitForIdle()
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items.first?.status, .available)
    }

    func testRefreshKeepsEveryRecordWithoutHistoryCap() throws {
        let store = try makeStore()
        let base = temporaryDirectory()
        for index in 0..<300 {
            try store.addItem(OutputInboxItem(
                fileURL: base.appendingPathComponent("row-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                status: .pending
            ))
        }

        let snapshot = try store.loadRefreshedItems()

        XCTAssertEqual(snapshot.count, 300, "no arbitrary history cap may drop records")
        XCTAssertEqual(snapshot.first?.fileURL.lastPathComponent, "row-299.wav")
        XCTAssertEqual(snapshot.last?.fileURL.lastPathComponent, "row-0.wav")
        XCTAssertTrue(snapshot.allSatisfy { $0.status == .missing })
    }

    // MARK: - Helpers

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

    @MainActor
    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 5,
        condition: @Sendable () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
            if Date() > deadline {
                XCTFail("Timed out waiting: \(message)")
                return
            }
        }
    }
}

/// In-memory `OutputInboxStore` with a gate on the first `loadRefreshedItems()`
/// pass, so tests can hold a refresh in-flight, mutate state, and assert the
/// main actor stays responsive and bursts coalesce.
private final class GatedInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: [OutputInboxItem]
    private var _loadCalls = 0
    private var _mainThreadObserved: Bool?
    private let gate = DispatchSemaphore(value: 0)
    private let blockFirstPass: Bool

    init(items: [OutputInboxItem], blockFirstPass: Bool = false) {
        self.snapshot = items
        self.blockFirstPass = blockFirstPass
    }

    var loadCalls: Int { lock.withLock { _loadCalls } }
    var mainThreadObserved: Bool? { lock.withLock { _mainThreadObserved } }

    func setItems(_ items: [OutputInboxItem]) {
        lock.withLock { snapshot = items }
    }

    func releaseFirstPass() {
        gate.signal()
    }

    func listItems() throws -> [OutputInboxItem] {
        lock.withLock { snapshot.sorted { $0.createdAt > $1.createdAt } }
    }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock { snapshot.append(item) }
    }

    func updateItem(_ item: OutputInboxItem) throws {
        lock.withLock {
            if let index = snapshot.firstIndex(where: { $0.id == item.id }) {
                snapshot[index] = item
            } else {
                snapshot.append(item)
            }
        }
    }

    func refreshAvailability() throws {
        _ = try loadRefreshedItems()
    }

    func loadRefreshedItems() throws -> [OutputInboxItem] {
        let call = lock.withLock { () -> Int in
            _loadCalls += 1
            if _mainThreadObserved == nil {
                _mainThreadObserved = Thread.isMainThread
            }
            return _loadCalls
        }
        if blockFirstPass, call == 1 {
            gate.wait()
        }
        return try listItems()
    }
}
