import AppCore
@testable import FeatureArchiveBrowser
import Combine
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectVaultPresentationCacheTests: XCTestCase {
    func testBoardSelectionDoesNotRepublishAlreadyCollapsedDisclosureState() {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        let first = Song(
            folderPath: URL(fileURLWithPath: "/tmp/project-vault-selection-first"),
            originalFolderName: "First",
            displayTitle: "First"
        )
        let second = Song(
            folderPath: URL(fileURLWithPath: "/tmp/project-vault-selection-second"),
            originalFolderName: "Second",
            displayTitle: "Second"
        )
        viewModel.selectedSong = first

        var publications = 0
        let observation = viewModel.objectWillChange.sink { _ in publications += 1 }
        viewModel.selectSongOnBoard(second)
        withExtendedLifetime(observation) {}

        XCTAssertEqual(viewModel.selectedSong?.id, second.id)
        XCTAssertEqual(
            publications,
            1,
            "Selecting a different card should publish its selection once; already-collapsed disclosures must stay no-ops."
        )
    }

    func testPresentationLookupUsesPreparedCacheAndPinRefreshesIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-vault-presentation-cache-\(UUID())", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let songFolder = active.appendingPathComponent("Fast Card", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let activeRoot = StoredMusicRoot(role: .active, url: active)
        var settings = AppSettings.default
        settings.musicRoots = [activeRoot]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeRoot.id,
            rolloutStage: .privateBeta
        )
        let store = CountingSettingsStore(settings: settings)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        let song = Song(
            folderPath: songFolder,
            originalFolderName: "Fast Card",
            displayTitle: "Fast Card"
        )

        XCTAssertTrue(viewModel.projectVaultPresentationContext != nil)
        let loadsBeforeCatalogUpdate = store.loadCount
        viewModel.songs = [song]
        XCTAssertEqual(viewModel.projectVaultPresentation(for: song)?.state, .active)
        XCTAssertEqual(
            store.loadCount,
            loadsBeforeCatalogUpdate,
            "Catalog updates must reuse the already prepared Vault settings context."
        )

        let loadsAfterPreparation = store.loadCount
        for _ in 0..<128 {
            XCTAssertEqual(viewModel.projectVaultPresentation(for: song)?.state, .active)
        }
        XCTAssertEqual(
            store.loadCount,
            loadsAfterPreparation,
            "Card presentation lookups must not deserialize settings during SwiftUI renders."
        )

        viewModel.setProjectKeepLocal(true, for: song)
        XCTAssertEqual(viewModel.projectVaultPresentation(for: song)?.state, .keepLocal)
        XCTAssertTrue(viewModel.projectVaultPresentation(for: song)?.isKeepLocal == true)

        let loadsAfterPinRefresh = store.loadCount
        for _ in 0..<128 {
            XCTAssertEqual(viewModel.projectVaultPresentation(for: song)?.state, .keepLocal)
        }
        XCTAssertEqual(
            store.loadCount,
            loadsAfterPinRefresh,
            "Pin updates must refresh the prepared cache rather than restoring render-time settings loads."
        )

        settings.vault.isEnabled = false
        try store.saveSettings(settings)
        viewModel.applyProjectVaultSettingsChange()
        XCTAssertNil(viewModel.projectVaultPresentation(for: song))
        XCTAssertNil(viewModel.projectVaultPresentationContext)

        let loadsAfterSettingsRefresh = store.loadCount
        for _ in 0..<128 {
            XCTAssertNil(viewModel.projectVaultPresentation(for: song))
        }
        XCTAssertEqual(
            store.loadCount,
            loadsAfterSettingsRefresh,
            "Applied settings changes must replace the prepared cache without render-time reloads."
        )
    }

    func testWaitingTransferNeverLabelsArchivedAndReadyRequiresFreshConfirmation() {
        let activeRecord = ProjectRecord(
            canonicalTitle: "Active Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Active Song", kind: .active, availability: .local)]
        )
        for waitingState in [VaultTransferState.awaitingProviderDurability, VaultTransferState.promotingArchiveGeneration] {
            let waiting = ProjectVaultCardPresentation(record: activeRecord, transferState: waitingState)
            XCTAssertEqual(waiting.state, .archiving, "\(waitingState)")
            XCTAssertEqual(waiting.statusLabel, "Waiting for upload", "\(waitingState)")
            XCTAssertFalse(waiting.statusLabel.contains("Archived"), "\(waitingState)")
            XCTAssertNotEqual(waiting.primaryAction, .restoreAndOpen, "\(waitingState)")
            XCTAssertEqual(
                ProjectVaultCardPresentation.transferStatusLabel(waitingState),
                "Waiting for upload",
                "\(waitingState)"
            )
            XCTAssertFalse(
                ProjectVaultCardPresentation.transferStatusLabel(waitingState).contains("Archived"),
                "\(waitingState)"
            )
        }

        let ready = ProjectVaultCardPresentation(record: activeRecord, isReadyToFreeSpace: true)
        XCTAssertEqual(ready.state, .active)
        XCTAssertEqual(ready.primaryAction, .freeUpSpace)
        XCTAssertEqual(ready.statusLabel, "Ready to free space")
        XCTAssertTrue(ready.explanation.contains("Nothing is removed until you confirm"))
        XCTAssertTrue(ready.isReadyToFreeSpace)

        let pinnedRecord = ProjectRecord(
            canonicalTitle: "Active Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Active Song", kind: .active, availability: .local)],
            pinned: true
        )
        let pinned = ProjectVaultCardPresentation(record: pinnedRecord, isReadyToFreeSpace: true)
        XCTAssertEqual(pinned.state, .keepLocal)
        XCTAssertNotEqual(pinned.primaryAction, .freeUpSpace)
        XCTAssertEqual(pinned.primaryAction, .openInCubase)
    }
}

private final class CountingSettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings
    private var loads = 0

    init(settings: AppSettings) {
        self.settings = settings
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loads
    }

    func loadSettings() throws -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        loads += 1
        return settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        self.settings = settings
    }

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        update(&settings)
    }
}
