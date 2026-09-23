import AppCore
import XCTest

/// Refresh-correction proofs for the Output Inbox.
///
/// The production path is `OutputInboxRefreshModel.requestRefresh()` (main
/// thread only enqueues) driving `JSONOutputInboxStore.loadRefreshedItems()`
/// (single load/scan/save/sort pass) on a background task. These tests prove:
/// main-thread responsiveness with a blocked store, burst coalescing without
/// a lost refresh, no lost concurrent updates, preserved identity/order,
/// quarantined (never deleted) corruption with a one-time warning, and
/// bounded missing history (available records are never pruned).
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

    func testCorruptInboxJSONIsQuarantinedInSameCall() throws {
        let badBytes = Data("{not-json".utf8)
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try badBytes.write(to: storage)
        let store = JSONOutputInboxStore(storageURL: storage)

        // Recovery happens in the same call: no throw, empty snapshot.
        XCTAssertEqual(try store.loadRefreshedItems(), [])

        let quarantineURL = try XCTUnwrap(
            store.lastQuarantineURL,
            "quarantine location must be recorded"
        )
        XCTAssertEqual(
            quarantineURL.deletingLastPathComponent().standardizedFileURL,
            directory.standardizedFileURL
        )
        XCTAssertTrue(
            quarantineURL.lastPathComponent.hasPrefix("inbox.corrupt-"),
            "quarantine must be unique and sit next to the store, got \(quarantineURL.lastPathComponent)"
        )
        XCTAssertEqual(quarantineURL.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: quarantineURL), badBytes)

        // The one-time warning drains exactly once.
        XCTAssertNotNil(store.takeCorruptionWarning())
        XCTAssertNil(store.takeCorruptionWarning())

        // The inbox is usable immediately: new output records normally.
        try store.addItem(OutputInboxItem(
            fileURL: directory.appendingPathComponent("fresh.wav"),
            sourceToolID: "dev-tool",
            status: .available
        ))
        XCTAssertEqual(try store.listItems().count, 1)

        // A second corruption episode gets its own quarantine file.
        try badBytes.write(to: storage)
        XCTAssertEqual(try store.loadRefreshedItems(), [])
        XCTAssertNotEqual(try XCTUnwrap(store.lastQuarantineURL), quarantineURL)
    }

    @MainActor
    func testModelSurfacesQuarantineWarningOnceThenClears() async throws {
        let badBytes = Data("{not-json".utf8)
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try badBytes.write(to: storage)
        let store = JSONOutputInboxStore(storageURL: storage)
        let model = OutputInboxRefreshModel(store: store)

        // Auto-recovery needs no manual fix: empty snapshot plus a visible
        // one-time warning through the existing error channel.
        model.requestRefresh()
        await model.waitForIdle()
        XCTAssertTrue(model.items.isEmpty)
        let warning = try XCTUnwrap(model.lastError)
        XCTAssertTrue(warning.contains("unreadable"), "got: \(warning)")
        let quarantineURL = try XCTUnwrap(store.lastQuarantineURL)
        XCTAssertEqual(try Data(contentsOf: quarantineURL), badBytes)

        // The next clean pass clears the warning; no restart required.
        model.requestRefresh()
        await model.waitForIdle()
        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.items.isEmpty)

        // New output flows through the recovered inbox and its scan.
        let file = directory.appendingPathComponent("back.wav")
        try Data("audio".utf8).write(to: file)
        try store.addItem(OutputInboxItem(
            fileURL: file,
            sourceToolID: "dev-tool",
            createdAt: Date(timeIntervalSince1970: 50),
            status: .pending
        ))

        model.requestRefresh()
        await model.waitForIdle()
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items.first?.status, .available)
    }

    func testRefreshKeepsRecordsWithinMissingCap() throws {
        // 300 missing rows sit under the bound, so every record survives.
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

        XCTAssertEqual(snapshot.count, 300, "records within the missing cap must survive")
        XCTAssertEqual(snapshot.first?.fileURL.lastPathComponent, "row-299.wav")
        XCTAssertEqual(snapshot.last?.fileURL.lastPathComponent, "row-0.wav")
        XCTAssertTrue(snapshot.allSatisfy { $0.status == .missing })
    }

    func testRefreshPrunesOnlyOldestMissingBeyondBound() throws {
        let bound = JSONOutputInboxStore.maxRetainedMissingCount
        let directory = temporaryDirectory()
        let storage = directory.appendingPathComponent("inbox.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Five available outputs older than every missing row: all must
        // survive regardless of age.
        var availableIDs: Set<UUID> = []
        var seeded: [OutputInboxItem] = []
        for index in 0..<5 {
            let url = directory.appendingPathComponent("keep-\(index).wav")
            try Data("audio".utf8).write(to: url)
            let item = OutputInboxItem(
                fileURL: url,
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                status: .pending
            )
            availableIDs.insert(item.id)
            seeded.append(item)
        }
        let missingTotal = bound + 200
        for index in 0..<missingTotal {
            seeded.append(OutputInboxItem(
                fileURL: directory.appendingPathComponent("gone-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(1000 + index)),
                status: .pending
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(seeded).write(to: storage, options: .atomic)
        let store = JSONOutputInboxStore(storageURL: storage)

        let snapshot = try store.loadRefreshedItems()

        XCTAssertEqual(snapshot.count, bound + 5, "only oldest missing beyond the bound may go")
        XCTAssertEqual(
            Set(snapshot.filter { $0.status == .available }.map(\.id)),
            availableIDs,
            "every available record survives, whatever its age"
        )
        let missingNewestFirst = seeded
            .filter { !availableIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        XCTAssertEqual(
            snapshot.filter { $0.status == .missing }.map(\.id),
            missingNewestFirst.prefix(bound).map(\.id),
            "the newest missing rows stay; the oldest 200 are pruned"
        )
        XCTAssertEqual(
            snapshot.map(\.createdAt),
            snapshot.map(\.createdAt).sorted(by: >),
            "newest-first ordering stays stable across the prune"
        )
        XCTAssertEqual(try store.listItems(), snapshot, "the pruned list must be persisted")
        let archived = try archivedItems(of: store)
        XCTAssertEqual(
            Set(archived.map(\.id)),
            Set(missingNewestFirst.dropFirst(bound).map(\.id)),
            "pruned rows are archived beside the store, not deleted"
        )
        XCTAssertEqual(store.trimmedArchiveURL.deletingLastPathComponent(), storage.deletingLastPathComponent())
    }

    /// An unplugged output drive makes every row missing at once; none may be trimmed, however
    /// many there are, because the files come back when the drive is reconnected.
    func testRowsOnAnUnmountedVolumeAreNeverTrimmed() throws {
        let bound = JSONOutputInboxStore.maxRetainedMissingCount
        let storage = temporaryDirectory().appendingPathComponent("inbox.json")
        let store = JSONOutputInboxStore(storageURL: storage)
        let volume = URL(fileURLWithPath: "/Volumes/NMH Unplugged \(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: volume.path))
        let rows = (0..<(bound + 200)).map { index in
            OutputInboxItem(
                fileURL: volume.appendingPathComponent("Exports/row-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                status: .available
            )
        }
        try seed(rows, at: storage)

        let snapshot = try store.loadRefreshedItems()

        XCTAssertEqual(Set(snapshot.map(\.id)), Set(rows.map(\.id)), "no row on an unreachable volume is trimmed")
        XCTAssertTrue(snapshot.allSatisfy { $0.status == .missing })
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.trimmedArchiveURL.path))
    }

    /// Only rows whose folder is there but whose file is gone count toward the cap; rows whose
    /// folder is gone are kept whatever their age.
    func testCapCountsOnlyRowsWhoseFolderStillExists() throws {
        let bound = JSONOutputInboxStore.maxRetainedMissingCount
        let storage = temporaryDirectory().appendingPathComponent("inbox.json")
        let store = JSONOutputInboxStore(storageURL: storage)
        let present = temporaryDirectory()
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        let removedFolder = temporaryDirectory().appendingPathComponent("Removed Output Folder")
        let unreachable = (0..<(bound + 50)).map { index in
            OutputInboxItem(
                fileURL: removedFolder.appendingPathComponent("old-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                status: .available
            )
        }
        let gone = (0..<(bound + 20)).map { index in
            OutputInboxItem(
                fileURL: present.appendingPathComponent("gone-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(10_000 + index)),
                status: .available
            )
        }
        try seed(unreachable + gone, at: storage)

        let snapshot = try store.loadRefreshedItems()
        let kept = Set(snapshot.map(\.id))

        XCTAssertTrue(Set(unreachable.map(\.id)).isSubset(of: kept), "rows whose folder is gone are never trimmed")
        let oldestGone = Set(gone.prefix(20).map(\.id))
        XCTAssertEqual(snapshot.count, unreachable.count + bound)
        XCTAssertTrue(oldestGone.isDisjoint(with: kept))
        XCTAssertEqual(Set(try archivedItems(of: store).map(\.id)), oldestGone)

        // A later trim adds to the archive instead of replacing it.
        let more = (0..<5).map { index in
            OutputInboxItem(
                fileURL: present.appendingPathComponent("later-\(index).wav"),
                sourceToolID: "volume",
                createdAt: Date(timeIntervalSince1970: Double(20_000 + index)),
                status: .available
            )
        }
        for item in more { try store.addItem(item) }
        _ = try store.loadRefreshedItems()
        XCTAssertEqual(
            Set(try archivedItems(of: store).map(\.id)),
            oldestGone.union(gone.dropFirst(20).prefix(5).map(\.id))
        )
    }

    private func seed(_ items: [OutputInboxItem], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    private func archivedItems(of store: JSONOutputInboxStore) throws -> [OutputInboxItem] {
        try JSONDecoder().decode([OutputInboxItem].self, from: Data(contentsOf: store.trimmedArchiveURL))
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
