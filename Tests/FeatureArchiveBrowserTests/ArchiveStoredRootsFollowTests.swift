import AppCore
import Combine
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import ProjectVaultRuntime
import XCTest

/// Settings, Set Up and the Project Vault pane save to the store and call
/// nothing; the archive follows every save through `appSettings`.
@MainActor
final class ArchiveStoredRootsFollowTests: XCTestCase {
    func testAFolderAddedByAnotherWriterIsLoadedAndScannedWithTheCatalogKept() async throws {
        let first = try makeFolder("first")
        let second = try makeFolder("second")
        defer { remove(first, second) }
        let store = try makeStore(scanning: [first])
        let gate = ScanGate(holdsScans: true)
        let viewModel = makeViewModel(store: store, gate: gate)
        let song = Song(
            folderPath: first.appendingPathComponent("Kept Song", isDirectory: true),
            originalFolderName: "Kept Song",
            displayTitle: "Kept Song"
        )
        viewModel.applyCatalogEdit(.load([song]))

        try store.updateSettings { $0 = ArchiveScanList().adding(second, bookmark: nil, to: $0) }

        try await waitUntil { gate.scannedRoots.count == 1 }
        XCTAssertEqual(Set(try XCTUnwrap(gate.scannedRoots.first).map(canonical)), Set([first, second].map(canonical)))
        XCTAssertEqual(viewModel.songs.map(\.id), [song.id], "an added folder keeps the catalog while it scans")
        XCTAssertEqual(viewModel.statusMessage, "Scanning archive...")
        gate.release()
    }

    func testAFolderRemovedByAnotherWriterClearsTheCatalogAndScansTheRest() async throws {
        let first = try makeFolder("first")
        let second = try makeFolder("second")
        defer { remove(first, second) }
        let store = try makeStore(scanning: [first, second])
        let gate = ScanGate(holdsScans: true)
        let viewModel = makeViewModel(store: store, gate: gate)
        viewModel.applyCatalogEdit(.load([Song(
            folderPath: first.appendingPathComponent("Gone Song", isDirectory: true),
            originalFolderName: "Gone Song",
            displayTitle: "Gone Song"
        )]))
        viewModel.recordPersistenceWarning("Unrelated warning.")

        try store.updateSettings { $0 = ArchiveScanList().removing(first, from: $0) }

        try await waitUntil { gate.scannedRoots.count == 1 }
        XCTAssertEqual(try XCTUnwrap(gate.scannedRoots.first).map(canonical), [canonical(second)])
        XCTAssertTrue(viewModel.songs.isEmpty, "a removal clears the root-bound state")
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Unrelated warning.", "an unrelated warning survives")
        gate.release()
    }

    func testVaultSwitchedOnByAnotherWriterLoadsTheActiveFolderAndRunsRecovery() async throws {
        let scanFolder = try makeFolder("scan")
        let activeFolder = try makeFolder("active")
        let archiveFolder = try makeFolder("archive")
        defer { remove(scanFolder, activeFolder, archiveFolder) }
        let store = try makeStore(scanning: [scanFolder])
        let runtime = RecoveryCountingVaultRuntime()
        let viewModel = makeViewModel(store: store, gate: ScanGate(holdsScans: false), vaultRuntime: runtime)
        try await waitUntilAsync { await runtime.recoveryCount() == 1 } // the launch recovery

        let active = StoredMusicRoot(role: .active, url: activeFolder)
        let archive = StoredMusicRoot(role: .archive, url: archiveFolder)
        try store.updateSettings { settings in
            settings.musicRoots += [active, archive]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = active.id
            settings.vault.archiveRootID = archive.id
        }

        try await waitUntilAsync { await runtime.recoveryCount() == 2 }
        XCTAssertEqual(
            Set(viewModel.roots.map(canonical)),
            Set([scanFolder, activeFolder].map(canonical)),
            "the Active folder joins the scan; the Archive folder never does"
        )
    }

    func testAKeepLocalPinLoadsNoRoots() async throws {
        let first = try makeFolder("first")
        let second = try makeFolder("second")
        defer { remove(first, second) }
        let store = try makeStore(scanning: [first])
        let gate = ScanGate(holdsScans: false)
        let viewModel = makeViewModel(store: store, gate: gate)
        let rootLoads = PublishCounter(viewModel.library.$roots.dropFirst())

        try store.updateSettings { $0.vault.keepLocalPins.pin(KeepLocalPins.Project(songIDs: ["pinned-song"])) }
        // Publishes arrive in save order: once the add is followed, the pin was too.
        try store.updateSettings { $0 = ArchiveScanList().adding(second, bookmark: nil, to: $0) }

        try await waitUntil { gate.scannedRoots.count == 1 }
        XCTAssertEqual(rootLoads.count, 1, "only the add loaded the roots")
        XCTAssertEqual(Set(try XCTUnwrap(gate.scannedRoots.first).map(canonical)), Set([first, second].map(canonical)))
    }

    func testTheArchivesOwnAddShowsAtOnceAndItsLaterPublishLoadsNothing() async throws {
        let first = try makeFolder("first")
        let second = try makeFolder("second")
        let third = try makeFolder("third")
        defer { remove(first, second, third) }
        let store = try makeStore(scanning: [first])
        let viewModel = makeViewModel(store: store, gate: ScanGate(holdsScans: false))
        let rootLoads = PublishCounter(viewModel.library.$roots.dropFirst())

        viewModel.addRoots([second])
        XCTAssertTrue(viewModel.roots.map(canonical).contains(canonical(second)), "the board shows its add at once")
        XCTAssertEqual(rootLoads.count, 1)

        // Another writer's save publishes after the add's own publish.
        try store.updateSettings { $0 = ArchiveScanList().adding(third, bookmark: nil, to: $0) }
        try await waitUntil { viewModel.roots.map(canonical).contains(canonical(third)) }
        XCTAssertEqual(rootLoads.count, 2, "the add's own publish loaded nothing again")
    }

    // MARK: - Helpers

    private func makeViewModel(
        store: UserDefaultsSettingsStore,
        gate: ScanGate,
        vaultRuntime: (any ProjectVaultOperating)? = nil
    ) -> ArchiveBrowserViewModel {
        // No watcher: init starts no scan, so every scan the gate sees comes from a root change.
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            projectVaultRuntime: vaultRuntime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: "ArchiveStoredRootsFollowTests",
            ]),
            scanOverride: { roots in try await gate.scan(roots) }
        )
    }

    private func makeStore(scanning folders: [URL]) throws -> UserDefaultsSettingsStore {
        let store = UserDefaultsSettingsStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: "ArchiveStoredRootsFollowTests.\(UUID())")),
            key: "settings"
        )
        try store.updateSettings { settings in
            settings.musicRoots = folders.map { StoredMusicRoot(role: .scanOnly, url: $0) }
            settings.archiveOnboardingCompleted = true
        }
        return store
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-follow-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func remove(_ folders: URL...) {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    private func canonical(_ url: URL) -> String {
        ArchiveScanList.canonicalPath(for: url)
    }

    /// Runs the main actor until `condition` holds; fails after two seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition did not hold within two seconds") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !(await condition()) {
            guard Date() < deadline else { return XCTFail("condition did not hold within two seconds") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// Records each scan's roots; a holding gate keeps the scan open until `release()`.
@MainActor
private final class ScanGate {
    private(set) var scannedRoots: [[URL]] = []
    private let holdsScans: Bool
    private var held: CheckedContinuation<ScanResult, any Error>?

    init(holdsScans: Bool) {
        self.holdsScans = holdsScans
    }

    func scan(_ roots: [URL]) async throws -> ScanResult {
        scannedRoots.append(roots)
        guard holdsScans else { return ScanResult() }
        return try await withCheckedThrowingContinuation { held = $0 }
    }

    func release() {
        held?.resume(returning: ScanResult())
        held = nil
    }
}

@MainActor
private final class PublishCounter {
    private(set) var count = 0
    private var subscription: AnyCancellable?

    init<P: Publisher>(_ publisher: P) where P.Failure == Never {
        subscription = publisher.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }
}

private actor RecoveryCountingVaultRuntime: ProjectVaultOperating {
    private var recoveries = 0

    func recoveryCount() -> Int { recoveries }

    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] { [] }

    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        throw ProjectVaultRuntimeError.unavailable
    }

    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func recoverAtLaunch() async {
        recoveries += 1
    }
}
