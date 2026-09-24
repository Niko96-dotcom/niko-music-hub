@testable import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class ProjectVaultPolishTests: XCTestCase {
    func testArchiveIntegrityFailureNamesChangedFileInsteadOfOfferingBlindRetry() {
        let record = ProjectRecord(canonicalTitle: "Changed Song", locations: [])
        let root = URL(fileURLWithPath: "/tmp/vault-fixture")
        var restore = VaultRestoreRecord(
            projectID: record.id, archiveGenerationURL: root.appendingPathComponent("generation"),
            stagingURL: root.appendingPathComponent("staging"), destinationURL: root.appendingPathComponent("active"),
            manifest: VaultManifest(entries: [])
        )
        restore.failureReason = .archiveGenerationIntegrityMismatch
        restore.error = "Archive verification failed: Song.cpr changed from 42 to 43 bytes since verification."
        let presentation = ProjectVaultCardPresentation(record: record, restore: restore)
        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertEqual(presentation.explanation, restore.error)
    }

    func testRestoreDrillUsesOnlyItsSyntheticTemporaryFixtureAndPreservesArchive() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let date = Date(timeIntervalSince1970: 123)

        let result = try ProjectVaultRestoreDrill(temporaryDirectory: parent, now: { date }).run()

        XCTAssertEqual(result.completedAt, date)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertTrue(result.archiveCopyPreserved)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: parent.path)).isEmpty)
    }

    func testDiagnosticsOmitsPathsAndRefusesMusicRootDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let music = root.appendingPathComponent("Secret Artist Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stored = StoredMusicRoot(role: .archive, url: music)
        var settings = AppSettings(musicRoots: [stored])
        settings.vault.archiveRootID = stored.id
        let health = ProjectVaultHealth(providerStatus: .availableLocal, lastSuccessfulVerificationAt: nil, hasIndependentBackup: false)

        let text = ProjectVaultDiagnosticsExporter.formattedText(settings: settings, health: health)
        XCTAssertFalse(text.contains(music.path))
        XCTAssertTrue(text.contains("provider_status=availableLocal"))
        XCTAssertThrowsError(try ProjectVaultDiagnosticsExporter.export(settings: settings, health: health, to: music.appendingPathComponent("diag.txt"))) {
            XCTAssertEqual($0 as? ProjectVaultDiagnosticsExportError, .destinationInsideMusicRoot)
        }
    }

    func testRolloutPolicyFailsClosedUntilFriendsStageAndBothRoots() {
        var settings = VaultSettings(
            isEnabled: true, activeRootID: UUID(), archiveRootID: UUID(),
            automaticArchiving: true
        )
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.rolloutStage = .friends
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.automationEmergencyStop = true
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
    }

    func testLegacyCopyOnlyNeverGainsRemovalThroughUpgrade() {
        let beta = VaultSettings(
            isEnabled: true, activeRootID: UUID(), archiveRootID: UUID(),
            rolloutStage: .privateBeta, independentBackupConfirmed: true
        )
        XCTAssertEqual(beta.spaceIntent, .keepCopy)
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(beta))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(beta))

        let disabled = VaultSettings(isEnabled: false, activeRootID: UUID(), archiveRootID: UUID())
        XCTAssertEqual(disabled.spaceIntent, .keepCopy)
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(disabled))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(disabled))
    }

    func testFreeSpaceIntentOrLegacyFriendsPermitsRemovalWithBackup() {
        let roots = (active: UUID(), archive: UUID())
        let legacy = VaultSettings(
            isEnabled: true, activeRootID: roots.active, archiveRootID: roots.archive,
            rolloutStage: .friends, independentBackupConfirmed: true
        )
        XCTAssertEqual(legacy.spaceIntent, .freeSpace)
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(legacy))

        var intent = VaultSettings(
            isEnabled: true, activeRootID: roots.active, archiveRootID: roots.archive,
            rolloutStage: .privateBeta, spaceIntent: .freeSpace, independentBackupConfirmed: true
        )
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(intent))
        XCTAssertTrue(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(intent))

        intent.independentBackupConfirmed = false
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(intent))

        intent.independentBackupConfirmed = true
        intent.automationEmergencyStop = true
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(intent))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(intent))
    }

    func testExplicitKeepCopyWithFriendsNeverAuthorizesRemoval() throws {
        let stored = VaultSettings(
            isEnabled: true, activeRootID: UUID(), archiveRootID: UUID(),
            rolloutStage: .friends, spaceIntent: .keepCopy, independentBackupConfirmed: true
        )
        XCTAssertEqual(stored.spaceIntent, .keepCopy)
        XCTAssertFalse(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(stored))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(stored))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(stored))

        var decoded = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"keepCopy","independentBackupConfirmed":true}"#.utf8)
        )
        decoded.activeRootID = UUID()
        decoded.archiveRootID = UUID()
        XCTAssertEqual(decoded.spaceIntent, .keepCopy)
        XCTAssertFalse(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(decoded))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(decoded))
    }

    func testInvalidSpaceIntentWithFriendsNeverEscalates() throws {
        let payload = Data(#"{"vault":{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"bogus","independentBackupConfirmed":true}}"#.utf8)
        // A present invalid intent now fails closed so an unrelated settings
        // edit cannot save defaults over the stored Vault choices or pins.
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: payload))
    }

    func testDisabledRolloutWithFreeSpaceIntentDeniesRemoval() {
        let settings = VaultSettings(
            isEnabled: true, activeRootID: UUID(), archiveRootID: UUID(),
            rolloutStage: .disabled, spaceIntent: .freeSpace, independentBackupConfirmed: true
        )
        XCTAssertTrue(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(settings))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(settings))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(settings))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings))
    }

    func testDoneEligibilityDecoupledFromSchedulerOptIn() {
        var settings = VaultSettings(
            isEnabled: true, activeRootID: UUID(), archiveRootID: UUID(),
            automaticArchiving: false, rolloutStage: .privateBeta
        )
        XCTAssertTrue(
            ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(settings),
            "user-initiated Done must not wait on the background scheduler opt-in"
        )
        XCTAssertFalse(
            ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings),
            "background scheduling stays opt-in"
        )
        settings.rolloutStage = .disabled
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(settings))
    }

    func testDiagnosticsReportsSpaceIntent() {
        var settings = AppSettings()
        settings.vault.spaceIntent = .freeSpace
        let health = ProjectVaultHealth(providerStatus: .availableLocal, lastSuccessfulVerificationAt: nil, hasIndependentBackup: false)
        XCTAssertTrue(ProjectVaultDiagnosticsExporter.formattedText(settings: settings, health: health).contains("space_intent=freeSpace"))
    }

    func testArchivedKeepLocalProjectStillRequiresRestoreBeforeOpen() {
        let record = ProjectRecord(
            canonicalTitle: "Archived Song",
            locations: [ProjectLocation(
                rootID: UUID(),
                relativePath: "generations/project/generation",
                kind: .archive,
                availability: .onlineOnly
            )],
            pinned: true
        )

        let presentation = ProjectVaultCardPresentation(record: record)

        XCTAssertTrue(presentation.isKeepLocal)
        XCTAssertEqual(presentation.state, .archived)
        XCTAssertEqual(presentation.primaryAction, .restoreAndOpen)
    }

    func testKeepLocalWithActiveCopyRemainsDirectlyOpenable() {
        let record = ProjectRecord(
            canonicalTitle: "Active Song",
            locations: [ProjectLocation(
                rootID: UUID(),
                relativePath: "Active Song",
                kind: .active,
                availability: .local
            )],
            pinned: true
        )

        let presentation = ProjectVaultCardPresentation(record: record)

        XCTAssertTrue(presentation.isKeepLocal)
        XCTAssertEqual(presentation.state, .keepLocal)
        XCTAssertEqual(presentation.primaryAction, .openInCubase)
    }

    func testFailedRecoverableOffersRetryWhileRecoveryRequiredStaysReviewOnly() {
        let record = ProjectRecord(canonicalTitle: "Retry Song", locations: [])

        let retryable = ProjectVaultCardPresentation(
            record: record,
            transferState: .failedRecoverable,
            transferErrorOrigin: .awaitingProviderDurability
        )
        let destructive = ProjectVaultCardPresentation(
            record: record,
            transferState: .failedRecoverable,
            transferErrorOrigin: .removingActiveCopy
        )
        let manualReview = ProjectVaultCardPresentation(record: record, transferState: .recoveryRequired)

        XCTAssertEqual(retryable.primaryAction, .retry)
        XCTAssertEqual(retryable.primaryAction.label, "Retry")
        XCTAssertEqual(destructive.primaryAction, .review)
        XCTAssertEqual(manualReview.primaryAction, .review)
    }

    func testDestructiveRecoveryRequiredReviewExplainsExactOriginWithoutOfferingMutation() {
        let record = ProjectRecord(canonicalTitle: "Interrupted Song", locations: [])
        let expectations: [(VaultTransferState, String)] = [
            (
                .removingActiveCopy,
                "Removing the Active folder was interrupted, so some or all of it may still be there. The Vault copy is still verified, and removal won’t restart on its own."
            ),
            (
                .evictingProviderCache,
                "The Active folder was removed, but clearing the cloud app’s offline copy was interrupted. The Vault copy is still verified, and this won’t restart on its own."
            ),
        ]
        var explanations: [String] = []

        for (origin, expectedExplanation) in expectations {
            let presentation = ProjectVaultCardPresentation(
                record: record,
                transferState: .recoveryRequired,
                transferErrorOrigin: origin
            )

            XCTAssertEqual(presentation.state, .needsAttention, "\(origin)")
            XCTAssertEqual(presentation.primaryAction, .review, "\(origin)")
            XCTAssertEqual(presentation.explanation, expectedExplanation, "\(origin)")
            XCTAssertNil(presentation.reviewAction, "\(origin)")
            XCTAssertNil(presentation.retryRestoreID, "\(origin)")
            explanations.append(presentation.explanation)
        }
        XCTAssertNotEqual(explanations[0], explanations[1])
    }

    func testActiveDestinationIntegrityMismatchIsReviewOnlyAcrossPostPromotionPhases() {
        let projectID = ProjectID()
        let activeDestination = URL(
            fileURLWithPath: "/tmp/disposable-active/Integrity Song",
            isDirectory: true
        )
        let record = ProjectRecord(
            id: projectID,
            canonicalTitle: "Integrity Song",
            locations: [ProjectLocation(
                rootID: UUID(),
                relativePath: "Integrity Song",
                kind: .active,
                availability: .local
            )]
        )
        let expectedExplanation = "The restored files changed after they were verified, so the project won’t open. Every copy was kept for you to check."

        for phase in [VaultRestorePhase.persistingActiveLocation, .openingInCubase] {
            var restore = VaultRestoreRecord(
                projectID: projectID,
                archiveGenerationURL: URL(
                    fileURLWithPath: "/tmp/disposable-vault/generations/project/generation",
                    isDirectory: true
                ),
                stagingURL: URL(
                    fileURLWithPath: "/tmp/disposable-active/.niko-staging/integrity",
                    isDirectory: true
                ),
                destinationURL: activeDestination,
                manifest: VaultManifest(entries: []),
                phase: phase
            )
            restore.failureReason = .activeDestinationIntegrityMismatch

            let presentation = ProjectVaultCardPresentation(record: record, restore: restore)

            XCTAssertEqual(presentation.state, .needsAttention, "\(phase)")
            XCTAssertEqual(presentation.primaryAction, .review, "\(phase)")
            XCTAssertEqual(presentation.explanation, expectedExplanation, "\(phase)")
            XCTAssertNil(presentation.reviewAction, "\(phase)")
            XCTAssertNil(presentation.retryRestoreID, "\(phase)")
        }
    }

    func testLegacyReviewRevealsExactGenerationAndRetriesSameRestore() {
        let generation = URL(fileURLWithPath: "/tmp/disposable-vault/generations/exact-generation", isDirectory: true)
        let restoreID = UUID()
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: ProjectID(),
            archiveGenerationURL: generation,
            stagingURL: URL(fileURLWithPath: "/tmp/disposable-active/.niko-staging/restore", isDirectory: true),
            destinationURL: URL(fileURLWithPath: "/tmp/disposable-active/Legacy Song", isDirectory: true),
            manifest: VaultManifest(entries: [])
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        let record = ProjectRecord(
            id: restore.projectID,
            canonicalTitle: "Legacy Song",
            locations: [ProjectLocation(
                rootID: UUID(),
                relativePath: "generations/exact-generation",
                kind: .archive,
                availability: .onlineOnly
            )]
        )

        let presentation = ProjectVaultCardPresentation(record: record, restore: restore)

        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertEqual(
            presentation.reviewAction,
            .makeAvailableOfflineInFinder(generationURL: generation)
        )
        XCTAssertEqual(presentation.retryRestoreID, restoreID)
        XCTAssertEqual(presentation.reviewAction?.label, "Make Available Offline in Finder")
    }

    func testSupersededLegacyRestoreIsReviewOnlyBeforeFailureDerivedActions() {
        let generation = URL(
            fileURLWithPath: "/tmp/disposable-vault/generations/project/generation",
            isDirectory: true
        )
        var restore = VaultRestoreRecord(
            projectID: ProjectID(),
            archiveGenerationURL: generation,
            stagingURL: URL(fileURLWithPath: "/tmp/disposable-active/.niko-staging/loser"),
            destinationURL: URL(fileURLWithPath: "/tmp/disposable-active/Legacy Song"),
            manifest: VaultManifest(entries: []),
            phase: .superseded
        )
        restore.supersededBy = UUID()
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        let record = ProjectRecord(
            id: restore.projectID,
            canonicalTitle: "Legacy Song",
            locations: []
        )

        let presentation = ProjectVaultCardPresentation(record: record, restore: restore)

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
    }

    func testGenerationResolverRequiresExactProjectAndTransferBindingWithoutHydratingOnlineOnlyPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectID = ProjectID()
        let transferID = UUID()
        let generationsRoot = root.appendingPathComponent("generations", isDirectory: true)
        let projectRoot = generationsRoot.appendingPathComponent(projectID.description, isDirectory: true)
        let exact = projectRoot.appendingPathComponent(
            "generation-\(transferID.uuidString.lowercased())",
            isDirectory: true
        )
        let wrongProject = generationsRoot
            .appendingPathComponent(ProjectID().description, isDirectory: true)
            .appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true)
        let wrongLeaf = projectRoot.appendingPathComponent("generation-\(UUID().uuidString.lowercased())", isDirectory: true)
        let extraDepth = exact.appendingPathComponent("nested", isDirectory: true)
        for candidate in [wrongProject, wrongLeaf] {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        }
        let resolver = try XCTUnwrap(ProjectVaultGenerationReviewResolver(archiveRootURL: root))

        XCTAssertTrue(resolver.isBoundGenerationPath(exact, projectID: projectID, transferID: transferID))
        XCTAssertNil(resolver.resolveGeneration(exact, projectID: projectID, transferID: transferID))

        try FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extraDepth, withIntermediateDirectories: true)
        XCTAssertEqual(
            resolver.resolveGeneration(exact, projectID: projectID, transferID: transferID),
            exact.standardizedFileURL
        )

        for candidate in [wrongProject, wrongLeaf, extraDepth] {
            XCTAssertFalse(
                resolver.isBoundGenerationPath(candidate, projectID: projectID, transferID: transferID),
                candidate.path
            )
            XCTAssertNil(
                resolver.resolveGeneration(candidate, projectID: projectID, transferID: transferID),
                candidate.path
            )
        }

        let https = URL(string: "https://example.invalid\(exact.path)")!
        let foreignFile = URL(string: "file://foreignhost\(exact.path)")!
        for candidate in [https, foreignFile] {
            XCTAssertFalse(resolver.isBoundGenerationPath(candidate, projectID: projectID, transferID: transferID))
            XCTAssertNil(resolver.resolveGeneration(candidate, projectID: projectID, transferID: transferID))
        }
    }

    func testSnapshotReadinessVerifiesManifestIDEnvelopeAndLocalRetained() throws {
        let valid = VaultManifest(entries: [VaultManifest.Entry(
            relativePath: "Song.cpr",
            type: .regularFile,
            byteCount: 3,
            modifiedAt: Date(timeIntervalSince1970: 1),
            sha256: String(repeating: "a", count: 64)
        )])
        XCTAssertNoThrow(try valid.validatePersistedContentEnvelope())

        let record = ProjectRecord(
            canonicalTitle: "Ready Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Song", kind: .active, availability: .local)]
        )
        var transfer = VaultTransferRecord(
            projectID: record.id,
            sourceURL: URL(fileURLWithPath: "/tmp/active/Song"),
            stagingURL: URL(fileURLWithPath: "/tmp/staging/Song"),
            destinationURL: URL(fileURLWithPath: "/tmp/archive/generation"),
            state: .archiveVerified
        )
        transfer.manifest = valid
        transfer.manifestID = valid.id
        XCTAssertEqual(transfer.manifestID, transfer.manifest?.id)

        var mismatched = transfer
        mismatched.manifestID = UUID()
        XCTAssertNotEqual(mismatched.manifestID, mismatched.manifest?.id)

        let invalid = VaultManifest(entries: [VaultManifest.Entry(
            relativePath: "/absolute",
            type: .regularFile,
            byteCount: 3,
            modifiedAt: Date(timeIntervalSince1970: 1),
            sha256: String(repeating: "b", count: 64)
        )])
        XCTAssertThrowsError(try invalid.validatePersistedContentEnvelope())

        let snapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
        XCTAssertTrue(snapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))
        XCTAssertFalse(snapshot.isReadyToFreeSpace(localActiveRetained: false, isBoundGeneration: true, isKeepLocal: false))
        XCTAssertFalse(snapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: false, isKeepLocal: false))
        XCTAssertFalse(snapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: true))

        let unbound = ProjectVaultRuntimeSnapshot(record: record, transfer: nil)
        XCTAssertFalse(unbound.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))
        XCTAssertNil(unbound.verifiedTerminalTransfer)
        XCTAssertNotNil(snapshot.verifiedTerminalTransfer)

        // Manifest-invalid readiness: mismatched ID, invalid envelope, and
        // project mismatch never verify, even with a terminal state.
        let mismatchedSnapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: mismatched)
        XCTAssertNil(mismatchedSnapshot.verifiedTerminalTransfer)
        XCTAssertFalse(mismatchedSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))

        var invalidTransfer = transfer
        invalidTransfer.manifest = invalid
        invalidTransfer.manifestID = invalid.id
        let invalidSnapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: invalidTransfer)
        XCTAssertNil(invalidSnapshot.verifiedTerminalTransfer)
        XCTAssertFalse(invalidSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))

        var missingManifest = transfer
        missingManifest.manifest = nil
        missingManifest.manifestID = nil
        let missingSnapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: missingManifest)
        XCTAssertNil(missingSnapshot.verifiedTerminalTransfer)
        XCTAssertFalse(missingSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))

        let otherRecord = ProjectRecord(canonicalTitle: "Other project", locations: record.locations)
        XCTAssertNotEqual(transfer.projectID, otherRecord.id)
        let wrongProjectSnapshot = ProjectVaultRuntimeSnapshot(record: otherRecord, transfer: transfer)
        XCTAssertNil(wrongProjectSnapshot.verifiedTerminalTransfer)
        XCTAssertFalse(wrongProjectSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))
    }

    func testSnapshotWaitingTransferIsNeverReadyToFreeSpace() {
        let record = ProjectRecord(
            canonicalTitle: "Waiting Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Song", kind: .active, availability: .local)]
        )
        var waiting = VaultTransferRecord(
            projectID: record.id,
            sourceURL: URL(fileURLWithPath: "/tmp/active/Song"),
            stagingURL: URL(fileURLWithPath: "/tmp/staging/Song"),
            destinationURL: URL(fileURLWithPath: "/tmp/archive/generation"),
            state: .awaitingProviderDurability
        )
        waiting.nextRetryAt = Date().addingTimeInterval(60)
        XCTAssertTrue(waiting.isWaitingForProviderUpload)
        let waitingSnapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: waiting)
        XCTAssertNil(waitingSnapshot.verifiedTerminalTransfer)
        XCTAssertFalse(waitingSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))

        var promoting = waiting
        promoting.state = .promotingArchiveGeneration
        XCTAssertTrue(promoting.isWaitingForProviderUpload)
        let promotingSnapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: promoting)
        XCTAssertFalse(promotingSnapshot.isReadyToFreeSpace(localActiveRetained: true, isBoundGeneration: true, isKeepLocal: false))

        let waitingPresentation = ProjectVaultCardPresentation(record: record, transferState: .awaitingProviderDurability)
        XCTAssertEqual(waitingPresentation.state, .archiving)
        XCTAssertEqual(waitingPresentation.statusLabel, "Waiting for upload")
        XCTAssertFalse(waitingPresentation.statusLabel.contains("Archived"))
        XCTAssertNotEqual(waitingPresentation.primaryAction, .restoreAndOpen)
    }

    func testCopyOnlyDowngradePreservesEveryBinding() {
        let authorization = ProjectVaultArchiveAuthorization(
            sourceCanonicalPath: "/Active/Ready Song",
            sourceFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 22),
            songID: "/Active/Ready Song",
            catalogProjectID: ProjectID(),
            activeRootID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            activeRootCanonicalPath: "/Active",
            activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 33),
            archiveRootID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            archiveRootCanonicalPath: "/Archive",
            archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 44, inode: 55),
            trigger: .manual,
            maximumDestructiveness: .mayRemoveActiveCopy,
            authorizedAt: Date(timeIntervalSince1970: 123_456)
        )
        let downgraded = authorization.downgradedToCopyOnly()
        XCTAssertEqual(downgraded.sourceCanonicalPath, authorization.sourceCanonicalPath)
        XCTAssertEqual(downgraded.sourceFileSystemIdentity, authorization.sourceFileSystemIdentity)
        XCTAssertEqual(downgraded.songID, authorization.songID)
        XCTAssertEqual(downgraded.catalogProjectID, authorization.catalogProjectID)
        XCTAssertEqual(downgraded.activeRootID, authorization.activeRootID)
        XCTAssertEqual(downgraded.activeRootCanonicalPath, authorization.activeRootCanonicalPath)
        XCTAssertEqual(downgraded.activeRootFileSystemIdentity, authorization.activeRootFileSystemIdentity)
        XCTAssertEqual(downgraded.archiveRootID, authorization.archiveRootID)
        XCTAssertEqual(downgraded.archiveRootCanonicalPath, authorization.archiveRootCanonicalPath)
        XCTAssertEqual(downgraded.archiveRootFileSystemIdentity, authorization.archiveRootFileSystemIdentity)
        XCTAssertEqual(downgraded.trigger, authorization.trigger)
        XCTAssertEqual(downgraded.authorizedAt, authorization.authorizedAt)
        XCTAssertEqual(downgraded.maximumDestructiveness, .copyOnly)
        XCTAssertFalse(downgraded.permitsRemoval)
        XCTAssertTrue(authorization.permitsRemoval)
        XCTAssertNotEqual(downgraded, authorization)
    }
}
