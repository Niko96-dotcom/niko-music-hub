import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class ProjectVaultPolishTests: XCTestCase {
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
        var settings = VaultSettings(isEnabled: true, activeRootID: UUID(), archiveRootID: UUID())
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.rolloutStage = .friends
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.automationEmergencyStop = true
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
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
                "Archive generation remains verified. Active-copy removal was interrupted, so the Active copy may or may not remain; automatic removal will not resume."
            ),
            (
                .evictingProviderCache,
                "Archive generation remains verified. Active-copy removal completed, but provider-cache eviction was interrupted; automatic eviction will not resume."
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
        let expectedExplanation = "The restored Active copy no longer matches the verified archive manifest. It will not be opened; existing copies were kept for review."

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
}
