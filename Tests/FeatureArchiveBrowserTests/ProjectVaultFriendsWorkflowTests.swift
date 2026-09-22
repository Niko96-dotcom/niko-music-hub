import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectVaultFriendsWorkflowTests: XCTestCase {
    func testLaunchRecoveryRefreshesSongsWithoutFilesystemWatcher() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime(projectOpener: LinkedFailOnceOpener())
        let launchSong = Song(folderPath: fixture.project,
            originalFolderName: fixture.project.lastPathComponent, displayTitle: "Recovery")
        let launchAuthorization = try await runtime.captureArchiveAuthorization(
            for: launchSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await runtime.archive(song: launchSong, trigger: .manual, authorization: launchAuthorization)
        do {
            _ = try await runtime.restoreAndOpen(snapshot: archived)
            XCTFail("Expected first open to fail")
        } catch {}
        let model = fixture.viewModel(runtime: runtime, archiveRootWatcher: nil)
        try await waitUntil { model.songs.contains { $0.folderPath.lastPathComponent == fixture.project.lastPathComponent } }
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
    }

    func testRestoreDialogSelectsVersionAndKeepsOccupiedDestination() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let chosen = fixture.project.appendingPathComponent("Chosen.als")
        try Data("older-ableton-version".utf8).write(to: chosen)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: chosen.path)
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let original = try XCTUnwrap(model.songs.first)
        let restoreDialogAuthorization = try await runtime.captureArchiveAuthorization(
            for: original, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(original, authorization: restoreDialogAuthorization)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        model.setShowArchivedProjects(true)
        let archived = try XCTUnwrap(model.songs.first)
        try FileManager.default.createDirectory(at: fixture.project, withIntermediateDirectories: true)
        let sentinel = fixture.project.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        model.performProjectVaultPrimaryAction(for: archived)
        try await waitUntil { model.projectVaultRestoreRequest != nil }
        let request = try XCTUnwrap(model.projectVaultRestoreRequest)
        XCTAssertTrue(request.options.versions.contains { $0.relativePath == "Chosen.als" })
        XCTAssertNotNil(request.options.destinationIssue(for: request.options.destinationRelativePath))
        model.confirmProjectVaultRestore(selectedPath: "Chosen.als")
        XCTAssertNotNil(model.projectVaultRestoreRequest)
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        model.confirmProjectVaultRestore(selectedPath: "Chosen.als", destinationRelativePath: "Restored separately")
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertNil(model.projectVaultRestoreRequest)
        XCTAssertTrue(model.projectVaultQueueFailures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        let destination = fixture.active.appendingPathComponent("Restored separately")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Chosen.als")), Data("older-ableton-version".utf8))
        let archive = try XCTUnwrap(fixture.transferStore().verifiedArchiveGeneration(projectID: fixture.projectID()))
        try VaultManifestBuilder().verify(try XCTUnwrap(archive.manifest), at: destination)
        try VaultManifestBuilder().verify(try XCTUnwrap(archive.manifest), at: archive.destinationURL)
    }

    func testLinkedArchiveRestoreDownloadsVerifiesAndPreservesIdentity() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let archive = fixture.archive.appendingPathComponent("Historical")
        try FileManager.default.copyItem(at: fixture.project, to: archive)
        let song = Song(folderPath: archive, originalFolderName: "Historical", displayTitle: "Historical")
        guard case .complete(let evidence, _) = try ProjectSourceInventory().collect(in: archive, for: song) else {
            return XCTFail("Missing fixture identity")
        }
        let location = ProjectLocation(rootID: fixture.archiveID, relativePath: "Historical", kind: .archive, availability: .onlineOnly)
        let entry = ProjectCatalogEntry(record: ProjectRecord(canonicalTitle: "Historical title",
            locations: [ProjectLocation(rootID: fixture.activeID, relativePath: "Old Name ", kind: .active, availability: .missing), location],
            workflowState: .done, lastActivityAt: Date(timeIntervalSince1970: 1234.125)), evidence: evidence)
        let catalog = try fixture.catalogStore()
        try catalog.apply(ProjectCatalogReconciliation(entries: [entry], reviews: [], metadataMigrations: [:]))
        let provider = LinkedDownloadProvider(root: fixture.archive, holdDownloads: true)
        let runtime = try fixture.runtime(provider: provider, projectOpener: LinkedFailOnceOpener())
        let model = fixture.viewModel(runtime: runtime, archiveRootWatcher: nil)
        await model.refreshProjectVaultSnapshots()
        await runtime.recoverAtLaunch()
        let snapshots = try await runtime.snapshots()
        let snapshot = try XCTUnwrap(snapshots.first { $0.record.id == entry.record.id })
        model.setShowArchivedProjects(true)
        let archivedSong = try XCTUnwrap(model.songs.first { $0.folderPath.lastPathComponent == "Historical" })
        model.performProjectVaultPrimaryAction(for: archivedSong)
        try await waitUntil { model.projectVaultRestoreRequest != nil }
        model.confirmProjectVaultRestore()
        try await provider.waitForDownloadStart()
        try await waitUntil { model.projectVaultRestoreProgress != nil }
        let progress = model.projectVaultRestoreProgress
        XCTAssertEqual(model.projectVaultActivityMessages[archivedSong.id], progress?.title)
        XCTAssertEqual(progress?.phase, .materializingArchive)
        XCTAssertEqual(progress?.fileCount, 2)
        XCTAssertEqual(progress?.totalBytes, fixture.sourceManifest.totalBytes)
        await provider.releaseDownload()
        try await waitUntil { !model.projectVaultBusySongIDs.contains(archivedSong.id) }
        XCTAssertNil(model.projectVaultRestoreProgress)
        XCTAssertTrue(model.projectVaultActivityMessages.isEmpty)
        let pendingSnapshots = try await runtime.snapshots()
        let pending = try XCTUnwrap(pendingSnapshots.first { $0.record.id == entry.record.id }?.restore)
        XCTAssertEqual(pending.phase, .openingInCubase)
        await model.refreshProjectVaultSnapshots()
        let activeSong = Song(folderPath: pending.destinationURL, originalFolderName: "Old Name ", displayTitle: "Historical title")
        model.songs = [activeSong]
        let retryPresentation = try XCTUnwrap(model.projectVaultPresentation(for: activeSong))
        XCTAssertEqual(retryPresentation.state, .needsAttention)
        XCTAssertEqual(retryPresentation.retryRestoreID, pending.id)
        XCTAssertEqual(retryPresentation.primaryActionLabel, "Retry Open")
        model.performProjectVaultPrimaryAction(for: activeSong)
        try await waitUntil { !model.projectVaultBusySongIDs.contains(activeSong.id) }
        let restored = try XCTUnwrap(fixture.transferStore().restoreRecord(id: pending.id))
        XCTAssertNotNil(restored.completedAt)
        XCTAssertNil(restored.archiveTransferID)
        XCTAssertEqual(restored.linkedArchiveLocation?.relativePath, "Historical")
        XCTAssertEqual(restored.destinationURL.lastPathComponent, "Old Name ")
        XCTAssertEqual(restored.projectID, entry.record.id)
        let downloads = await provider.downloads
        XCTAssertEqual(downloads, 1)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: restored.destinationURL)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: archive)
        let persisted = try XCTUnwrap(catalog.loadEntries().first { $0.record.id == entry.record.id })
        XCTAssertEqual(persisted.record.canonicalTitle, entry.record.canonicalTitle)
        XCTAssertEqual(persisted.record.lastActivityAt, entry.record.lastActivityAt)
        XCTAssertEqual(persisted.record.locations.first { $0.kind == .archive }, location)
        XCTAssertEqual(persisted.evidence, evidence)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        // A repeated request must not overwrite the now occupied Active folder.
        do {
            _ = try await runtime.restoreAndOpen(snapshot: snapshot)
            XCTFail("Occupied destination must be preserved")
        } catch {}
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: restored.destinationURL)
    }

    func testLinkedArchiveOffersRestoreAndPreservesHistoricalMetadata() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let archived = fixture.archive.appendingPathComponent("Existing Archive")
        try FileManager.default.copyItem(at: fixture.project, to: archived)
        let observedSong = Song(folderPath: archived, originalFolderName: "Existing Archive", displayTitle: "Existing Archive")
        guard case .complete(let evidence, _) = try ProjectSourceInventory().collect(in: archived, for: observedSong) else {
            return XCTFail("Fixture inventory must be complete")
        }
        let historicPath = fixture.active.appendingPathComponent("Old Name ")
        let entry = ProjectCatalogEntry(
            record: ProjectRecord(
                canonicalTitle: "Preserved title",
                locations: [ProjectLocation(rootID: fixture.activeID, relativePath: "Old Name ", kind: .active, availability: .missing)],
                workflowState: .done
            ),
            evidence: evidence
        )
        let store = try fixture.catalogStore()
        try store.apply(ProjectCatalogReconciliation(entries: [entry], reviews: [], metadataMigrations: [:]))
        try store.linkArchiveLocations([ProjectCatalogArchiveLink(
            projectID: entry.record.id,
            location: ProjectLocation(rootID: fixture.archiveID, relativePath: "Existing Archive", kind: .archive, availability: .onlineOnly),
            evidence: evidence
        )])
        let metadataStore = try SQLiteSongUserMetadataStore(database: fixture.database)
        try metadataStore.upsert(SongUserMetadata(songID: historicPath.path, virtualTitle: "My existing title", appNote: "Historical note", workflowStatus: .done))
        let revealed = RevealedURLBox()
        let runtime = try fixture.runtime()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.settingsStore, fileActions: CapturingTestFileActions(revealed: revealed)),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.dryRunOpenKey: "1"])
        )
        await viewModel.refreshProjectVaultSnapshots()
        XCTAssertEqual(viewModel.archivedProjectCount, 1)
        viewModel.setShowArchivedProjects(true)
        let song = try XCTUnwrap(viewModel.songs.first { $0.folderPath.lastPathComponent == "Existing Archive" })
        XCTAssertEqual(song.effectiveDisplayTitle, "My existing title")
        XCTAssertEqual(song.appNote, "Historical note")
        let snapshot = try XCTUnwrap(viewModel.projectVaultSnapshot(for: song))
        XCTAssertEqual(snapshot.record.id, entry.record.id)
        XCTAssertEqual(snapshot.linkedArchive?.location.availability, .local, "Fresh file metadata must replace the stale stored online-only flag.")
        XCTAssertNil(snapshot.transfer)
        XCTAssertNil(snapshot.record.lastVerifiedAt)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: song))
        XCTAssertEqual(presentation.state, .archived)
        XCTAssertEqual(presentation.primaryAction, .restoreAndOpen)
        XCTAssertTrue(viewModel.blocksGenericProjectVaultFileActions(for: song))
        let openBlockReason = try XCTUnwrap(viewModel.projectOpenBlockReason(for: song))
        XCTAssertTrue(openBlockReason.contains("Get Local & Open"))
        XCTAssertThrowsError(try viewModel.openLatestCPR(for: song))
        XCTAssertEqual(viewModel.statusMessage, openBlockReason)
        XCTAssertNil(viewModel.lastDryRunLog)
        XCTAssertFalse(viewModel.canArchiveInProjectVault(song))
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: song))
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: archived)

        let online = ProjectVaultCardPresentation(record: snapshot.record, linkedArchiveAvailability: .onlineOnly)
        XCTAssertEqual(online.primaryAction, .restoreAndOpen)
        XCTAssertTrue(online.explanation.contains("online-only"))

        let reopened = fixture.viewModel(runtime: try fixture.runtime(), songMetadataStore: metadataStore)
        await reopened.refreshProjectVaultSnapshots()
        reopened.setShowArchivedProjects(true)
        // The launch scan adds an active song ahead of the archive projection.
        // Exercise that ordering before checking the historical project's metadata.
        try await waitUntil {
            !reopened.isScanning && reopened.scannedSongs.contains {
                $0.folderPath.resolvingSymlinksInPath() == fixture.project.resolvingSymlinksInPath()
            }
        }
        XCTAssertEqual(reopened.archivedProjectCount, 1)
        let reopenedSong = try XCTUnwrap(reopened.songs.first {
            reopened.projectVaultSnapshot(for: $0)?.record.id == entry.record.id
        })
        XCTAssertEqual(reopenedSong.effectiveDisplayTitle, "My existing title")
        XCTAssertEqual(reopenedSong.appNote, "Historical note")
        let persistedEntry = try XCTUnwrap(store.loadEntries().first { $0.record.id == entry.record.id })
        XCTAssertEqual(persistedEntry.record.locations.first { $0.kind == .active }?.relativePath, "Old Name ")

        // A cached card is never authority after the configured archive root changes.
        try fixture.settingsStore.updateSettings { $0.vault.archiveRootID = UUID() }
        viewModel.performProjectVaultPrimaryAction(for: song)
        try await waitUntil { !viewModel.projectVaultBusySongIDs.contains(song.id) }
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
    }

    func testRapidArchiveAndRestoreRequestsQueueAndDeduplicate() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let second = try fixture.addSong(named: "Second Ableton", extension: "als")
        let secondManifest = try VaultManifestBuilder().build(at: second)
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let firstSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let secondSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == second.lastPathComponent })
        let firstAuthorization = try await runtime.captureArchiveAuthorization(
            for: firstSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let secondAuthorization = try await runtime.captureArchiveAuthorization(
            for: secondSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(firstSong, authorization: firstAuthorization)
        model.archiveInProjectVault(secondSong, authorization: secondAuthorization)
        model.archiveInProjectVault(secondSong, authorization: secondAuthorization)
        model.archiveInProjectVault(firstSong, authorization: firstAuthorization)
        XCTAssertEqual(model.projectVaultActiveOperation?.songID, firstSong.id)
        XCTAssertEqual(model.projectVaultPendingOperations.map(\.songID), [secondSong.id])
        XCTAssertEqual(model.projectVaultQueueMessage(for: secondSong), "Queued: Archive — 1 ahead.")
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 2)
        XCTAssertTrue(model.projectVaultQueueFailures.isEmpty)

        model.setShowArchivedProjects(true)
        let archived = model.songs
        XCTAssertEqual(archived.count, 2)
        for song in archived {
            model.performProjectVaultPrimaryAction(for: song)
            model.performProjectVaultPrimaryAction(for: song)
            try await waitUntil { model.projectVaultRestoreRequest != nil }
            model.confirmProjectVaultRestore()
        }
        XCTAssertLessThanOrEqual(model.projectVaultPendingOperations.count, 1)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(secondManifest, at: second)
        XCTAssertTrue(model.projectVaultQueueFailures.isEmpty)
    }

    func testFailedArchiveContinuesWithNextSongAndKeepsFailureVisible() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let second = try fixture.addSong(named: "Second Cubase", extension: "cpr")
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let firstSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let secondSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == second.lastPathComponent })
        let failedAuthorization = try await runtime.captureArchiveAuthorization(
            for: firstSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(firstSong, authorization: failedAuthorization)
        model.archiveInProjectVault(secondSong, trigger: .backupCopy)
        // Only a disposable fixture disappears before the first queued task starts.
        try FileManager.default.removeItem(at: fixture.project)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(model.projectVaultQueueFailures, [firstSong.effectiveDisplayTitle])
        XCTAssertTrue(model.statusBaseMessage?.contains("Needs attention:") == true)
        XCTAssertTrue(model.projectVaultOperationMessages[firstSong.id]?.contains("did not complete") == true)
        XCTAssertTrue(model.projectVaultOperationMessages[secondSong.id]?.contains("Backup copy verified") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCancelWaitingArchiveDoesNotCancelRunningBackup() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let second = try fixture.addSong(named: "Cancelled Cubase", extension: "cpr")
        let secondManifest = try VaultManifestBuilder().build(at: second)
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let firstSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let secondSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == second.lastPathComponent })
        let cancelledAuthorization = try await runtime.captureArchiveAuthorization(
            for: secondSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(firstSong, trigger: .backupCopy)
        model.archiveInProjectVault(secondSong, authorization: cancelledAuthorization)
        model.cancelQueuedProjectVaultOperation(for: secondSong)
        XCTAssertTrue(model.projectVaultPendingOperations.isEmpty)
        XCTAssertEqual(model.projectVaultActiveOperation?.songID, firstSong.id)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        try VaultManifestBuilder().verify(secondManifest, at: second)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testCancelActiveTransferDoesNotRemoveActive() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let provider = FriendsHoldingWriteProvider(root: fixture.archive)
        let model = fixture.viewModel(runtime: try fixture.runtime(provider: provider))
        await model.scan()
        let song = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let archiveRootBefore = fixture.archive

        model.archiveInProjectVault(song, trigger: .backupCopy)
        try await waitUntil { provider.didStartWrite }
        XCTAssertEqual(model.projectVaultActiveOperation?.songID, song.id)

        model.requestStopActiveProjectVaultTransfer()
        XCTAssertTrue(model.pendingStopTransferConfirmation)
        model.keepActiveProjectVaultTransfer()
        XCTAssertFalse(model.pendingStopTransferConfirmation)
        XCTAssertEqual(model.projectVaultActiveOperation?.songID, song.id)

        model.requestStopActiveProjectVaultTransfer()
        model.confirmStopActiveProjectVaultTransfer()
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveRootBefore.path))
        XCTAssertFalse(
            try fixture.transferStore().allTransferRecords().contains {
                VaultTransferOwnershipPolicy.isVerifiedTerminal($0.state)
            }
        )
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
    }

    func testQueuedArchiveRechecksEmergencyStopAtDispatch() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let second = try fixture.addSong(named: "Waiting Cubase", extension: "cpr")
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let firstSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let secondSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == second.lastPathComponent })
        let emergencyAuthorization = try await runtime.captureArchiveAuthorization(
            for: secondSong, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.enqueueProjectVaultOperation(for: firstSong, label: "Test", startMessage: "Test") { _ in
            do {
                try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
                return true
            } catch {
                XCTFail("Could not update Emergency Stop: \(error)")
                return false
            }
        }
        model.archiveInProjectVault(secondSong, authorization: emergencyAuthorization)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(model.projectVaultOperationMessages[secondSong.id]?.contains("Emergency Stop") == true)
        XCTAssertFalse(try fixture.transferStore().allTransferRecords().contains { $0.state == .archivedOnlineOnly })
    }

    func testQueuedArchiveCancelsWhenConfiguredFoldersChange() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        let foldersAuthorization = try await runtime.captureArchiveAuthorization(
            for: song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(song, authorization: foldersAuthorization)
        try fixture.settingsStore.updateSettings { $0.vault.archiveRootID = UUID() }
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        XCTAssertTrue(model.projectVaultOperationMessages[song.id]?.contains("folders changed") == true)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testLockAccessFailureEndsRequestAndAllowsNextQueuedBackup() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let second = try fixture.addSong(named: "After Lock Failure", extension: "cpr")
        let model = fixture.viewModel(runtime: try fixture.runtime())
        await model.scan()
        let firstSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let secondSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == second.lastPathComponent })
        var attempts = 0
        model.enqueueProjectVaultOperation(for: firstSong, label: "Test", startMessage: "Test") { model in
            do {
                try await model.waitForProjectVaultSlot {
                    attempts += 1
                    throw ProjectVaultRuntimeError.mutationLockUnavailable(EACCES)
                }
                return true
            } catch {
                model.setProjectVaultStatusMessage(error.localizedDescription)
                return false
            }
        }
        model.archiveInProjectVault(secondSong, trigger: .backupCopy)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.projectVaultQueueFailures, [firstSong.effectiveDisplayTitle])
        XCTAssertTrue(model.projectVaultOperationMessages[firstSong.id]?.contains("operation lock") == true)
        XCTAssertTrue(model.projectVaultOperationMessages[secondSong.id]?.contains("Backup copy verified") == true)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testQueueWaitsForBusyRuntimeAdmissionWithoutDroppingRequest() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let model = fixture.viewModel(runtime: try fixture.runtime())
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        var attempts = 0
        model.enqueueProjectVaultOperation(for: song, label: "Test", startMessage: "Test") { model in
            do {
                try await model.waitForProjectVaultSlot {
                    attempts += 1
                    if attempts == 1 { throw ProjectVaultRuntimeError.mutationInProgress }
                }
                return true
            } catch { return false }
        }
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(model.projectVaultQueueFailures.isEmpty)
    }

    func testManualArchiveLeavesNormalBoardAndReturnsAfterRestore() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings {
            $0.vault.rolloutStage = .privateBeta
            $0.vault.automaticArchiving = false
        }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let original = try XCTUnwrap(viewModel.songs.first)
        viewModel.archiveInProjectVault(original, trigger: .backupCopy)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(viewModel.songs.contains { $0.id == original.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        let manualAuthorization = try await runtime.captureArchiveAuthorization(
            for: original, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        viewModel.archiveInProjectVault(original, authorization: manualAuthorization)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertFalse(viewModel.songs.contains { $0.id == original.id })
        viewModel.setShowArchivedProjects(true)
        let archived = try XCTUnwrap(viewModel.songs.first)
        XCTAssertEqual(viewModel.projectVaultPresentation(for: archived)?.primaryAction, .restoreAndOpen)
        viewModel.performProjectVaultPrimaryAction(for: archived)
        try await waitUntil { viewModel.projectVaultRestoreRequest != nil }
        viewModel.confirmProjectVaultRestore()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        viewModel.setShowArchivedProjects(false)
        XCTAssertTrue(viewModel.songs.contains { $0.id == original.id })
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        let restored = try XCTUnwrap(viewModel.songs.first { $0.id == original.id })
        XCTAssertNil(viewModel.projectVaultQueueMessage(for: restored))
    }

    func testMountedBrowserResumesPendingUploadWithoutClaimingSuccess() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let provider = FriendsDelayedUploadProvider(pending: true)
        let runtime = try fixture.runtime(
            provider: provider,
            recoveryPolicy: .init(maximumAutomaticAttempts: 3, initialBackoff: 1, maximumBackoff: 2)
        )
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first)
        viewModel.updateWorkflowStatus(for: song, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        let store = try fixture.transferStore()
        try await waitUntil {
            (try? store.allTransferRecords().first?.state) == .awaitingProviderDurability
                && viewModel.projectVaultBusySongIDs.isEmpty
        }
        var failed = try XCTUnwrap(try store.allTransferRecords().first)
        XCTAssertTrue(failed.isWaitingForProviderUpload)
        XCTAssertTrue(viewModel.statusMessage?.contains("Waiting for cloud upload") == true)
        XCTAssertEqual(try XCTUnwrap(failed.nextRetryAt).timeIntervalSince(failed.updatedAt), 60, accuracy: 0.001)
        // Bring the persisted deadline forward to exercise the real mounted timer.
        failed.nextRetryAt = Date().addingTimeInterval(0.2)
        try store.save(failed)
        let due = try XCTUnwrap(failed.nextRetryAt)
        XCTAssertEqual(failed.retryCount, 0)
        XCTAssertGreaterThan(due, Date())
        // Snapshot refreshes must not postpone or multiply the pending timer.
        for _ in 0..<3 { await viewModel.refreshProjectVaultSnapshots() }
        // The recovery task clears its deadline before it refreshes snapshots,
        // so also wait until the view model has observed the verified transfer.
        try await waitUntil {
            (try? store.record(id: failed.id)?.state) == .archiveVerified
                && viewModel.projectVaultRecoveryDeadline == nil
                && viewModel.projectVaultSnapshot(for: song)?.transfer?.state == .archiveVerified
        }
        let completed = try XCTUnwrap(try store.record(id: failed.id))
        XCTAssertGreaterThanOrEqual(Date(), due)
        XCTAssertEqual(try store.allTransferRecords().count, 1)
        XCTAssertEqual(completed.durability, .syncedToProvider)
        XCTAssertNil(viewModel.projectVaultQueueMessage(for: song))
        XCTAssertFalse(viewModel.statusMessage?.contains("Waiting for cloud upload") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: completed.destinationURL)
        let barriers = await provider.barrierCount()
        XCTAssertEqual(barriers, 3, "One timeout, then staging and final-generation confirmation")
    }

    func testMountedBrowserResumesTimedOutCopyAtPersistedDeadlineWithoutAnotherTransfer() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let provider = FriendsDelayedUploadProvider()
        let runtime = try fixture.runtime(
            provider: provider,
            recoveryPolicy: .init(maximumAutomaticAttempts: 3, initialBackoff: 1, maximumBackoff: 2)
        )
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first)
        viewModel.updateWorkflowStatus(for: song, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        let store = try fixture.transferStore()
        try await waitUntil {
            (try? store.allTransferRecords().first?.state) == .failedRecoverable
                && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let failed = try XCTUnwrap(try store.allTransferRecords().first)
        let due = try XCTUnwrap(failed.nextRetryAt)
        XCTAssertEqual(failed.retryCount, 1)
        XCTAssertGreaterThan(due, Date())
        // Snapshot refreshes must not postpone or multiply the pending timer.
        for _ in 0..<3 { await viewModel.refreshProjectVaultSnapshots() }
        try await waitUntil {
            (try? store.record(id: failed.id)?.state) == .archiveVerified
                && viewModel.projectVaultRecoveryDeadline == nil
        }
        let completed = try XCTUnwrap(try store.record(id: failed.id))
        XCTAssertGreaterThanOrEqual(Date(), due)
        XCTAssertEqual(try store.allTransferRecords().count, 1)
        XCTAssertEqual(completed.durability, .syncedToProvider)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: completed.destinationURL)
        let barriers = await provider.barrierCount()
        XCTAssertEqual(barriers, 3, "One timeout, then staging and final-generation confirmation")
    }

    func testEmergencyStopCancelsPendingMountedBrowserRecovery() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let provider = FriendsDelayedUploadProvider()
        let runtime = try fixture.runtime(
            provider: provider,
            recoveryPolicy: .init(maximumAutomaticAttempts: 3, initialBackoff: 1, maximumBackoff: 2)
        )
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        viewModel.updateWorkflowStatus(for: try XCTUnwrap(viewModel.songs.first), status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultRecoveryDeadline != nil }
        try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
        await viewModel.refreshProjectVaultSnapshots()
        XCTAssertNil(viewModel.projectVaultRecoveryDeadline)
        try await Task.sleep(for: .milliseconds(1200))
        let records = try fixture.transferStore().allTransferRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.state, .failedRecoverable)
        let barriers = await provider.barrierCount()
        XCTAssertEqual(barriers, 1)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
    }

    func testCopyOnlyThenDonePreservesMetadataAndCorruptRestoreCanBeRetried() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let metadataStore = try SQLiteSongUserMetadataStore(database: fixture.database)
        let viewModel = fixture.viewModel(runtime: runtime, songMetadataStore: metadataStore)
        await viewModel.scan()
        let original = try XCTUnwrap(viewModel.songs.first)
        viewModel.updateAliases(for: original, aliasesText: "safety alias")
        viewModel.updateAppNote(for: original, note: "Retain this note across the Vault lifecycle")
        let active = try XCTUnwrap(viewModel.songs.first)

        // Create Backup Copy creates the generation before the later Done transition.
        _ = try await runtime.archive(song: active, trigger: .backupCopy)
        await viewModel.refreshProjectVaultSnapshots()
        viewModel.updateWorkflowStatus(for: active, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        viewModel.setShowArchivedProjects(true)
        try await waitUntil {
            !FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let archived = try XCTUnwrap(viewModel.songs.first)
        XCTAssertEqual(archived.aliases, ["safety alias"])
        XCTAssertEqual(archived.appNote, active.appNote)
        XCTAssertEqual(archived.workflowStatus, .done)
        viewModel.updateAppNote(for: archived, note: "Do not create orphaned archive metadata")
        XCTAssertEqual(try metadataStore.loadAll()[original.id]?.appNote, active.appNote)
        XCTAssertNil(try metadataStore.loadAll()[archived.id])

        let transfer = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(projectID: fixture.projectID()))
        let archiveAudio = transfer.destinationURL.appendingPathComponent("Audio/take.wav")
        let goodBytes = try Data(contentsOf: archiveAudio)
        var corrupted = goodBytes
        corrupted[0] ^= 0xff
        try corrupted.write(to: archiveAudio)
        viewModel.performProjectVaultPrimaryAction(for: archived)
        try await waitUntil { viewModel.projectVaultRestoreRequest != nil }
        viewModel.confirmProjectVaultRestore()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        let failed = try XCTUnwrap(viewModel.projectVaultPresentation(for: archived))
        XCTAssertEqual(failed.state, .needsAttention)
        let restoreID = try XCTUnwrap(failed.retryRestoreID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        viewModel.retryReviewedProjectVaultRestore(for: archived)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertNil(try fixture.transferStore().restoreRecord(id: restoreID)?.completedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        try goodBytes.write(to: archiveAudio)
        viewModel.retryReviewedProjectVaultRestore(for: archived)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertNotNil(try fixture.transferStore().restoreRecord(id: restoreID)?.completedAt)
        let restored = try XCTUnwrap(viewModel.songs.first { $0.id == original.id })
        XCTAssertEqual(restored.aliases, ["safety alias"])
        XCTAssertEqual(restored.appNote, active.appNote)
        XCTAssertEqual(restored.workflowStatus, .done)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: transfer.destinationURL)
    }

    func testArchiveOnlyProjectionRejectsWorkflowMutationAndFSEventDoesNotPromoteIt() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let sibling = fixture.active.appendingPathComponent("Still Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data("still-active-cpr".utf8)
            .write(to: sibling.appendingPathComponent("Still Active.cpr"))

        let watcher = TestArchiveRootWatcher()
        let indexStore = ProjectVaultRecordingArchiveIndexStore()
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(
            runtime: runtime,
            archiveIndexStore: indexStore,
            archiveRootWatcher: watcher
        )

        await viewModel.scan()
        let activeSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.updateWorkflowStatus(for: activeSong, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        viewModel.setShowArchivedProjects(true)

        try await waitUntil {
            !FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.songs.contains {
                    $0.originalFolderName == "Friends Workflow Song"
                        && viewModel.projectVaultPresentation(for: $0)?.state == .archived
                }
        }

        let archivedSong = try XCTUnwrap(viewModel.songs.first {
            $0.originalFolderName == "Friends Workflow Song"
                && viewModel.projectVaultPresentation(for: $0)?.state == .archived
        })
        let archivePath = archivedSong.folderPath.standardizedFileURL.path
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: archivedSong))
        XCTAssertFalse(ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(
            for: viewModel.projectVaultPresentation(for: archivedSong)
        ))

        viewModel.selectedSong = archivedSong
        viewModel.applyCatalogScanUpdate(
            ArchiveCatalogCoordinator.CatalogScanApplyResult(
                songs: viewModel.scannedSongs,
                diagnostics: try XCTUnwrap(viewModel.scanDiagnostics),
                statusMessage: "Fixture scan update",
                scannedAt: Date(),
                shouldPersistUserMetadata: false
            ),
            roots: viewModel.roots
        )
        XCTAssertEqual(viewModel.selectedSong?.id, archivedSong.id)
        XCTAssertTrue(
            viewModel.songs.contains { $0.folderPath.standardizedFileURL.path == archivePath },
            "A scan apply must synchronously retain the opt-in archive projection."
        )

        viewModel.updateWorkflowStatus(for: archivedSong, status: .prod)
        XCTAssertEqual(
            viewModel.songs.first(where: { $0.folderPath.standardizedFileURL.path == archivePath })?.workflowStatus,
            .done,
            "Archive-only cards are restore targets and must not accept workflow edits."
        )

        _ = await viewModel.indexPersistTask?.value
        let persistedSnapshotCount = indexStore.savedSnapshots.count
        let mixdownFolder = sibling.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Still Active mix.wav")
        try Data("incremental-mixdown".utf8).write(to: mixdown)
        watcher.simulateFilesystemChange(paths: [mixdown])

        try await waitUntil {
            viewModel.songs.first(where: { $0.originalFolderName == "Still Active" })?
                .previewCandidates.isEmpty == false
        }
        _ = await viewModel.indexPersistTask?.value

        XCTAssertGreaterThan(indexStore.savedSnapshots.count, persistedSnapshotCount)
        XCTAssertTrue(
            viewModel.songs.contains { $0.folderPath.standardizedFileURL.path == archivePath },
            "The visible archive projection should survive an unrelated active-root FSEvent."
        )
        XCTAssertFalse(
            viewModel.scannedSongs.contains { $0.folderPath.standardizedFileURL.path == archivePath },
            "An archive projection must not become scanner baseline state."
        )
        let persisted = try XCTUnwrap(indexStore.savedSnapshots.last)
        XCTAssertFalse(
            persisted.songs.contains { $0.folderPath.standardizedFileURL.path == archivePath },
            "An archive projection must not be written into the scanner index after an FSEvent."
        )
    }

    func testOnlineOnlyDropboxGenerationRemainsVisibleWithoutLocalArchiveFolder() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)

        await viewModel.scan()
        let activeSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.updateWorkflowStatus(for: activeSong, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        viewModel.setShowArchivedProjects(true)

        try await waitUntil {
            !FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.songs.contains { $0.originalFolderName == "Friends Workflow Song" }
        }

        let transferStore = try fixture.transferStore()
        var transfer = try XCTUnwrap(try transferStore.verifiedArchiveGeneration(projectID: fixture.projectID()))
        try FileManager.default.removeItem(at: transfer.destinationURL)
        transfer.state = .archivedOnlineOnly
        try transferStore.save(transfer)

        await viewModel.refreshProjectVaultSnapshots()

        let archivedSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        XCTAssertTrue(archivedSong.projectVersions.isEmpty, "The online-only generation should not be read as local files")
        XCTAssertEqual(viewModel.projectVaultPresentation(for: archivedSong)?.state, .archived)
        XCTAssertEqual(viewModel.projectVaultPresentation(for: archivedSong)?.primaryAction, .restoreAndOpen)
    }

    func testFriendsArchiveRemainsVisibleRestoresVerifiesAndKeepsLocalAcrossRelaunch() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)

        await viewModel.scan()
        let activeSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.updateWorkflowStatus(for: activeSong, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        XCTAssertFalse(viewModel.showArchivedProjects)
        viewModel.setShowArchivedProjects(true)

        try await waitUntil {
            !FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.songs.contains {
                    $0.originalFolderName == "Friends Workflow Song"
                        && viewModel.projectVaultPresentation(for: $0) != nil
                }
        }

        let workflowSongs = viewModel.songs.filter { $0.originalFolderName == "Friends Workflow Song" }
        XCTAssertEqual(workflowSongs.count, 1, "Unexpected project paths: \(workflowSongs.map(\.folderPath.path))")
        let archivedSong = try XCTUnwrap(workflowSongs.first)
        XCTAssertNotEqual(archivedSong.folderPath.standardizedFileURL, fixture.project.standardizedFileURL)
        let archivedPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))
        XCTAssertEqual(archivedPresentation.state, .archived)
        XCTAssertEqual(archivedPresentation.primaryAction, .restoreAndOpen)

        viewModel.setShowArchivedProjects(false)
        XCTAssertFalse(viewModel.songs.contains { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.setShowArchivedProjects(true)
        let reShownArchivedSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })

        viewModel.setProjectKeepLocal(true, for: reShownArchivedSong)
        let pinnedArchivedPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: reShownArchivedSong))
        XCTAssertTrue(pinnedArchivedPresentation.isKeepLocal)
        XCTAssertEqual(pinnedArchivedPresentation.state, .archived)
        XCTAssertEqual(pinnedArchivedPresentation.primaryAction, .restoreAndOpen)

        viewModel.performProjectVaultPrimaryAction(for: reShownArchivedSong)
        try await waitUntil { viewModel.projectVaultRestoreRequest != nil }
        viewModel.confirmProjectVaultRestore()
        try await waitUntil {
            FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.statusMessage == "Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there."
        }

        let restoredSong = try XCTUnwrap(viewModel.songs.first { $0.folderPath.standardizedFileURL == fixture.project.standardizedFileURL })
        let restoredPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: restoredSong))
        XCTAssertTrue(restoredPresentation.isKeepLocal)
        XCTAssertEqual(restoredPresentation.state, .keepLocal)
        XCTAssertEqual(restoredPresentation.primaryAction, .openInCubase)

        let transfer = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(projectID: fixture.projectID()))
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)

        do {
            _ = try await runtime.archive(song: restoredSong, trigger: .workflowDone)
            XCTFail("Keep Local must block later automatic archiving")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocal)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        let relaunchedRuntime = try fixture.runtime()
        await relaunchedRuntime.recoverAtLaunch()
        let relaunchedViewModel = fixture.viewModel(runtime: relaunchedRuntime)
        await relaunchedViewModel.scan()
        relaunchedViewModel.setShowArchivedProjects(true)
        await relaunchedViewModel.refreshProjectVaultSnapshots()

        XCTAssertEqual(
            relaunchedViewModel.songs.filter { $0.originalFolderName == "Friends Workflow Song" }.count,
            1
        )
        let relaunchedSong = try XCTUnwrap(relaunchedViewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        XCTAssertEqual(relaunchedViewModel.projectVaultPresentation(for: relaunchedSong)?.state, .keepLocal)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)
    }

    func testPersistedVerifiedActiveReconstructsReadyToFreeSpaceAfterFreshViewModel() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let original = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.archiveInProjectVault(original, trigger: .backupCopy)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        await viewModel.refreshProjectVaultSnapshots()
        let readySong = try XCTUnwrap(viewModel.songs.first { $0.id == original.id })
        let readyPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: readySong))
        XCTAssertEqual(readyPresentation.state, .active)
        XCTAssertEqual(readyPresentation.primaryAction, .freeUpSpace)
        XCTAssertTrue(readyPresentation.isReadyToFreeSpace)
        XCTAssertEqual(readyPresentation.statusLabel, "Ready to free space")

        let freshRuntime = try fixture.runtime()
        await freshRuntime.recoverAtLaunch()
        let freshViewModel = fixture.viewModel(runtime: freshRuntime)
        await freshViewModel.scan()
        await freshViewModel.refreshProjectVaultSnapshots()
        try await waitUntil { freshViewModel.songs.contains { $0.id == original.id } }
        await freshViewModel.refreshProjectVaultSnapshots()
        let freshSong = try XCTUnwrap(freshViewModel.songs.first { $0.id == original.id })
        let freshPresentation = try XCTUnwrap(freshViewModel.projectVaultPresentation(for: freshSong))
        XCTAssertEqual(freshPresentation.state, .active)
        XCTAssertEqual(freshPresentation.primaryAction, .freeUpSpace)
        XCTAssertTrue(freshPresentation.isReadyToFreeSpace)
        XCTAssertEqual(freshPresentation.statusLabel, "Ready to free space")
        XCTAssertTrue(freshPresentation.explanation.contains("fresh confirmation"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        let transfer = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(projectID: fixture.projectID()))
        XCTAssertTrue(VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state))
        XCTAssertEqual(transfer.manifestID, transfer.manifest?.id)
        let persistedManifest = try XCTUnwrap(transfer.manifest)
        XCTAssertNoThrow(try persistedManifest.validatePersistedContentEnvelope())
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)
        let snapshots = try await freshRuntime.snapshots()
        let snapshot = try XCTUnwrap(snapshots.first { $0.record.id == transfer.projectID })
        XCTAssertTrue(snapshot.record.locations.contains { $0.kind == .active })
        XCTAssertNotNil(snapshot.transfer)
        XCTAssertTrue(VaultTransferOwnershipPolicy.isVerifiedTerminal(snapshot.transfer?.state ?? .activeLocal))
    }

    func testWaitingProviderTransferNeverPresentsAsArchived() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let provider = FriendsDelayedUploadProvider(pending: true)
        let runtime = try fixture.runtime(
            provider: provider,
            recoveryPolicy: .init(maximumAutomaticAttempts: 3, initialBackoff: 1, maximumBackoff: 2)
        )
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.updateWorkflowStatus(for: song, status: .done)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        let store = try fixture.transferStore()
        try await waitUntil {
            (try? store.allTransferRecords().first?.state) == .awaitingProviderDurability
                && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let waiting = try XCTUnwrap(try store.allTransferRecords().first)
        XCTAssertTrue(waiting.isWaitingForProviderUpload)
        await viewModel.refreshProjectVaultSnapshots()
        let waitingSong = try XCTUnwrap(viewModel.songs.first { $0.id == song.id })
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: waitingSong))
        XCTAssertEqual(presentation.transferState, .awaitingProviderDurability)
        XCTAssertEqual(presentation.state, .archiving)
        XCTAssertEqual(presentation.statusLabel, "Waiting for upload")
        XCTAssertFalse(presentation.statusLabel.contains("Archived"))
        XCTAssertNotEqual(presentation.primaryAction, .restoreAndOpen)
        XCTAssertEqual(ProjectVaultCardPresentation.transferStatusLabel(.awaitingProviderDurability), "Waiting for upload")
        XCTAssertEqual(ProjectVaultCardPresentation.transferStatusLabel(.promotingArchiveGeneration), "Waiting for upload")
        XCTAssertFalse(ProjectVaultCardPresentation.transferStatusLabel(.awaitingProviderDurability).contains("Archived"))
    }

    func testKeepLocalAndPauseSuppressReadyToFreeSpaceOffer() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let original = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.archiveInProjectVault(original, trigger: .backupCopy)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        await viewModel.refreshProjectVaultSnapshots()
        let readySong = try XCTUnwrap(viewModel.songs.first { $0.id == original.id })
        XCTAssertEqual(viewModel.projectVaultPresentation(for: readySong)?.primaryAction, .freeUpSpace)

        viewModel.setProjectKeepLocal(true, for: readySong)
        let pinned = try XCTUnwrap(viewModel.projectVaultPresentation(for: readySong))
        XCTAssertTrue(pinned.isKeepLocal)
        XCTAssertEqual(pinned.state, .keepLocal)
        XCTAssertEqual(pinned.primaryAction, .openInCubase)
        XCTAssertFalse(pinned.isReadyToFreeSpace)
        XCTAssertNotEqual(pinned.primaryAction, .freeUpSpace)

        viewModel.setProjectKeepLocal(false, for: readySong)
        await viewModel.refreshProjectVaultSnapshots()
        XCTAssertEqual(viewModel.projectVaultPresentation(for: readySong)?.primaryAction, .freeUpSpace)

        try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
        viewModel.refreshProjectVaultPresentationContext()
        let paused = try XCTUnwrap(viewModel.projectVaultPresentation(for: readySong))
        XCTAssertFalse(paused.isReadyToFreeSpace)
        XCTAssertNotEqual(paused.primaryAction, .freeUpSpace)
        XCTAssertEqual(paused.state, .active)
        XCTAssertEqual(paused.primaryAction, .openInCubase)
        XCTAssertFalse(paused.statusLabel.contains("Ready to free space"))
    }

    func testPersistedFreeSpaceActionInvokesFreshCaptureNotStaleApproval() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let original = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.archiveInProjectVault(original, trigger: .backupCopy)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        await viewModel.refreshProjectVaultSnapshots()
        let readySong = try XCTUnwrap(viewModel.songs.first { $0.id == original.id })
        XCTAssertEqual(viewModel.projectVaultPresentation(for: readySong)?.primaryAction, .freeUpSpace)

        let stale = try await runtime.captureArchiveAuthorization(
            for: readySong, trigger: .workflowDone, removingActiveCopy: false, catalogProjectID: nil)
        XCTAssertEqual(stale.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(stale.trigger, .workflowDone)

        viewModel.performProjectVaultPrimaryAction(for: readySong)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .manual)
        XCTAssertEqual(pending.songID, readySong.id)
        let fresh = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(fresh.trigger, .manual)
        XCTAssertEqual(fresh.maximumDestructiveness, .mayRemoveActiveCopy)
        XCTAssertNotEqual(fresh, stale)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
        viewModel.cancelPendingArchive()
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for Friends workflow state")
    }
}

private struct FriendsClearActivityProbe: VaultAutomationActivityProbing {
    func cubaseStatus() async -> VaultActivityStatus { .clear }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
}

final class FriendsWorkflowFixture {
    let root: URL
    let active: URL
    let archive: URL
    let project: URL
    let sourceManifest: VaultManifest
    let database: SQLiteArchiveDatabase
    let settingsStore: UserDefaultsSettingsStore
    let activeID = UUID()
    let archiveID = UUID()
    let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("friends-workflow-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        project = active.appendingPathComponent("Friends Workflow Song", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("friends-workflow-cpr".utf8)
            .write(to: project.appendingPathComponent("Friends Workflow Song.cpr"))
        try Data(repeating: 0x5a, count: 16_384)
            .write(to: project.appendingPathComponent("Audio/take.wav"))
        sourceManifest = try VaultManifestBuilder().build(at: project)
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        suite = "ProjectVaultFriendsWorkflowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settingsStore = UserDefaultsSettingsStore(userDefaults: defaults)
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: active),
            StoredMusicRoot(id: archiveID, role: .archive, url: archive),
        ]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            automaticArchiving: true,
            independentBackupConfirmed: true
        )
        settings.vault.setSpaceIntent(.freeSpace)
        try settingsStore.saveSettings(settings)
    }

    func addSong(named name: String, extension fileExtension: String) throws -> URL {
        let folder = active.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture-project".utf8).write(to: folder.appendingPathComponent("\(name).\(fileExtension)"))
        return folder
    }

    func runtime(
        provider: (any ArchiveStorageProvider)? = nil,
        projectOpener: any VaultProjectOpening = SafeVaultProjectOpener(),
        recoveryPolicy: VaultTransferRecoveryPolicy = .production
    ) throws -> LiveProjectVaultRuntime {
        try LiveProjectVaultRuntime(
            settingsStore: settingsStore,
            transferStore: transferStore(),
            catalogStore: catalogStore(),
            projectOpener: projectOpener,
            activityProbe: FriendsClearActivityProbe(),
            capacityProbe: FriendsSafeCapacityProbe(),
            archiveProviderFactory: { root in provider ?? LocalFolderArchiveStorage(root: root) },
            recoveryPolicy: recoveryPolicy
        )
    }

    @MainActor
    func viewModel(
        runtime: any ProjectVaultOperating,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = NoopArchiveRootWatcher()
    ) -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            archiveRootWatcher: archiveRootWatcher,
            projectVaultRuntime: runtime,
            projectCatalogStore: try? catalogStore(),
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: suite,
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            ])
        )
    }

    func transferStore() throws -> SQLiteVaultTransferStore {
        try SQLiteVaultTransferStore(database: database)
    }

    func catalogStore() throws -> SQLiteProjectCatalogStore {
        try SQLiteProjectCatalogStore(database: database)
    }

    func projectID() throws -> ProjectID {
        try XCTUnwrap(try catalogStore().loadEntries().first?.record.id)
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FriendsHoldingWriteProvider: ArchiveStorageProvider, @unchecked Sendable {
    private let local: LocalFolderArchiveStorage
    private let lock = NSLock()
    private var started = false

    init(root: URL) {
        local = LocalFolderArchiveStorage(root: root)
    }

    var didStartWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    private func markStarted() {
        lock.lock()
        started = true
        lock.unlock()
    }

    func capabilities() async throws -> StorageCapabilities {
        try await local.capabilities()
    }
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        try await local.currentLocality(at: location, manifest: manifest)
    }
    func prepareForRead(_ location: URL) async throws {
        try await local.prepareForRead(location)
    }
    func prepareForWrite(at root: URL) async throws {
        markStarted()
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CancellationError()
    }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        try await local.waitUntilDurable(location)
    }
    func materialize(_ location: URL) async throws {
        try await local.materialize(location)
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        try await local.evictIfSupported(location)
    }
}

private actor FriendsDelayedUploadProvider: ArchiveStorageProvider {
    let pending: Bool
    init(pending: Bool = false) { self.pending = pending }
    private var barriers = 0
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: false, supportsEviction: false)
    }
    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        if barriers == 1 { throw pending ? FileProviderArchiveStorageError.uploadPending : FileProviderArchiveStorageError.durabilityUnavailable }
        return .syncedToProvider
    }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
    func barrierCount() -> Int { barriers }
}

private struct FriendsSafeCapacityProbe: ProjectVaultCapacityProbing {
    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 500 * 1_073_741_824,
            archiveAvailableCapacityBytes: 500 * 1_073_741_824,
            projectedArchiveBytes: 1_073_741_824
        )
    }
}

private final class ProjectVaultRecordingArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    private(set) var savedSnapshots: [ArchiveIndexSnapshot] = []

    func loadLatest() throws -> ArchiveIndexSnapshot? { nil }

    func save(_ snapshot: ArchiveIndexSnapshot) throws {
        savedSnapshots.append(snapshot)
    }

    func clear() throws {}
}

private actor LinkedDownloadProvider: ArchiveStorageProvider {
    let local: LocalFolderArchiveStorage
    var downloads = 0
    var holdDownloads: Bool
    var downloadStarted = false
    init(root: URL, holdDownloads: Bool = false) {
        local = LocalFolderArchiveStorage(root: root)
        self.holdDownloads = holdDownloads
    }
    func waitForDownloadStart() async throws {
        for _ in 0..<250 {
            if downloadStarted { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ProjectVaultRuntimeError.unavailable
    }
    func releaseDownload() { holdDownloads = false }
    func capabilities() async throws -> StorageCapabilities {
        StorageCapabilities(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        downloads == 0 ? .materializationRequired : .fullyLocalCurrent
    }
    func prepareForRead(_ location: URL) async throws { try await local.prepareForRead(location) }
    func prepareForWrite(at root: URL) async throws { try await local.prepareForWrite(at: root) }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {
        downloadStarted = true
        while holdDownloads { try await Task.sleep(for: .milliseconds(20)) }
        downloads += 1
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private final class LinkedFailOnceOpener: VaultProjectOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        let fail = lock.withLock {
            let first = !didFail
            didFail = true
            return first
        }
        if fail { throw LocalVaultRestoreError.noSupportedProject }
        return try SafeVaultProjectOpener().openProject(at: projectURL, allowedRoot: allowedRoot)
    }
}
