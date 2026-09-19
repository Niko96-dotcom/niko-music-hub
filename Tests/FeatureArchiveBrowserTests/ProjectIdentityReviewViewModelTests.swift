import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectIdentityReviewViewModelTests: XCTestCase {
    func testPendingAmbiguityRemainsVisibleUntilExplicitResolution() {
        let review = ProjectIdentityReview(
            existingProjectID: ProjectID(),
            candidateProjectID: ProjectID(),
            reason: "Conflicting fixture evidence"
        )
        let viewModel = ProjectIdentityReviewViewModel(reviews: [review])

        XCTAssertEqual(viewModel.pendingReviews.map(\.id), [review.id])

        XCTAssertTrue(viewModel.resolve(review.id, as: .keepSeparate))

        XCTAssertTrue(viewModel.pendingReviews.isEmpty)
        XCTAssertEqual(viewModel.reviews.first?.resolution, .keepSeparate)
    }

    func testResolvePersistsKeepSeparate() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-008-identity-review-\(UUID().uuidString).sqlite")
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteProjectCatalogStore(databaseURL: databaseURL)
        let existingID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let candidateID = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Conflicting fixture evidence"
        )
        try store.apply(ProjectCatalogReconciliation(
            entries: [ProjectCatalogEntry(
                record: ProjectRecord(
                    id: existingID,
                    canonicalTitle: "Fixture Song",
                    locations: [ProjectLocation(
                        rootID: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                        relativePath: "Fixture Song",
                        kind: .active
                    )]
                ),
                evidence: ProjectIdentityEvidence(folderName: "Fixture Song", cubaseFiles: [])
            )],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = ProjectIdentityReviewViewModel(reviews: [review], catalogStore: store)
        XCTAssertTrue(viewModel.resolve(review.id, as: .keepSeparate))

        XCTAssertTrue(viewModel.pendingReviews.isEmpty)
        XCTAssertEqual(viewModel.reviews.first?.resolution, .keepSeparate)
        XCTAssertEqual(try store.loadReviews().first?.resolution, .keepSeparate)

        let reopened = try SQLiteProjectCatalogStore(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.loadReviews().map(\.id), [review.id])
        XCTAssertEqual(try reopened.loadReviews().first?.resolution, .keepSeparate)
        XCTAssertEqual(try reopened.loadEntries().map(\.record.id), [existingID])
    }

    func testIdentityAmbiguousPresentsReviewAndKeepSeparateAllowsArchive() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let first = ProjectID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        let second = ProjectID(rawValue: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        try seedDuplicateCatalogEntries(on: fixture, projectIDs: [first, second])

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.archiveInProjectVault(song, trigger: .manual)
        try await waitUntil {
            viewModel.identityReviewPresentation != nil && viewModel.projectVaultBusySongIDs.isEmpty
        }

        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.title, song.effectiveDisplayTitle)
        XCTAssertEqual(
            presentation.message,
            ProjectIdentityReviewCopy.message(title: song.effectiveDisplayTitle, reason: presentation.review.reason)
        )
        XCTAssertTrue(presentation.message.contains("Nothing is archived until you choose."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)

        // V2: identity resolution itself NEVER archives. A still-resolving
        // initiating song earns a fresh explicit Archive Now confirmation.
        // V3: that fresh confirmation captures its bound authorization first.
        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertTrue(viewModel.identityReviewViewModel.pendingReviews.isEmpty)
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == presentation.review.id }?.resolution,
            .keepSeparate
        )
        let confirmation = try XCTUnwrap(
            viewModel.pendingArchiveConfirmation,
            "explicit Link/Keep Separate flow requires fresh Archive Now confirmation"
        )
        _ = try XCTUnwrap(confirmation.authorization, "V3 fresh confirmation must carry its captured token")
        XCTAssertEqual(confirmation.trigger, .manual)
        XCTAssertEqual(confirmation.songID, song.id)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)

        viewModel.confirmPendingArchive()

        try await waitUntil {
            viewModel.pendingArchiveConfirmation == nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let transfers = try fixture.transferStore().allTransferRecords()
        XCTAssertFalse(transfers.isEmpty, viewModel.statusMessage ?? "confirmed archive produced no transfer")
        XCTAssertTrue(
            transfers.contains { VaultTransferOwnershipPolicy.isVerifiedTerminal($0.state) },
            viewModel.statusMessage ?? "confirmed archive did not finish a verified generation"
        )
    }

    func testPendingReviewsPresentOnAppearAndCancelDoesNotRetryArchive() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let existingID = ProjectID()
        let candidateID = ProjectID()
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [
                ProjectCatalogEntry(
                    record: ProjectRecord(id: existingID, canonicalTitle: "Friends Workflow Song", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
                ProjectCatalogEntry(
                    record: ProjectRecord(id: candidateID, canonicalTitle: "Friends Workflow Song copy", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
            ],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        XCTAssertNil(viewModel.identityReviewPresentation)

        viewModel.presentPendingIdentityReviewsIfNeeded()

        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.review.id, review.id)
        XCTAssertEqual(presentation.title, "Friends Workflow Song")
        // V2 stable identity: entries carry no locations, so no song binds by
        // title alone, and a persisted review invents no authorization.
        XCTAssertNil(
            presentation.song,
            "persisted review must not bind an unrelated same-title song by title"
        )
        XCTAssertNil(presentation.trigger)
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        viewModel.cancelPresentedIdentityReview()

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertEqual(viewModel.identityReviewViewModel.pendingReviews.map(\.id), [review.id])
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertEqual(try fixture.catalogStore().loadReviews().first?.resolution, .pending)
    }

    func testIdentityReviewSheetIsWiredInShippingArchiveBrowser() throws {
        let browser = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            encoding: .utf8
        )
        let sheet = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ProjectIdentityReviewSheet.swift",
            encoding: .utf8
        )

        XCTAssertTrue(browser.contains("identityReviewPresentation"))
        XCTAssertTrue(browser.contains("ProjectIdentityReviewSheet"))
        XCTAssertTrue(browser.contains("presentPendingIdentityReviewsIfNeeded"))
        XCTAssertTrue(sheet.contains("Review Duplicate Project"))
        XCTAssertTrue(sheet.contains("Keep Separate"))
        XCTAssertTrue(sheet.contains("Link"))
        XCTAssertTrue(sheet.contains("Cancel"))
        XCTAssertTrue(sheet.contains("keyboardShortcut(.defaultAction)"))
        XCTAssertTrue(sheet.contains("keyboardShortcut(.cancelAction)"))
        XCTAssertTrue(sheet.contains("Nothing is archived until you choose."))
    }

    // Adapted from .codex/audit-context.patch: a persisted review resolved on
    // appear must not queue a manual archive without an explicit Archive
    // Now/Done confirmation, and must not bind an unrelated same-title song by
    // title/folder match alone. The incidental audit assertion expecting the
    // wrong song is removed; stable identity binds nothing here.
    func testPersistedReviewResolveOnAppearMustNotQueueManualArchiveWithoutConfirmation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let existingID = ProjectID()
        let candidateID = ProjectID()
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [
                ProjectCatalogEntry(
                    record: ProjectRecord(id: existingID, canonicalTitle: "Friends Workflow Song", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
                ProjectCatalogEntry(
                    record: ProjectRecord(id: candidateID, canonicalTitle: "Friends Workflow Song copy", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
            ],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let unrelated = try XCTUnwrap(
            viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent },
            "fixture song must be scanned before presenting the persisted review"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.folderPath.path))

        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.review.id, review.id)
        XCTAssertNil(presentation.trigger, "persisted review carries no authorization")
        XCTAssertNil(
            presentation.song,
            "stable identity must not bind the unrelated same-title song by title"
        )
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(
            viewModel.pendingArchiveConfirmation,
            "persisted review resolution must not bypass explicit Archive Now/Done confirmation"
        )
        let queuedManualArchive = viewModel.projectVaultBusySongIDs.contains(unrelated.id)
            || viewModel.projectVaultActiveOperation?.songID == unrelated.id
            || viewModel.projectVaultPendingOperations.contains(where: { $0.songID == unrelated.id })
        XCTAssertFalse(
            queuedManualArchive,
            "pending persisted review resolution alone queued a manual archive for an unrelated same-title song without confirmation"
        )
        XCTAssertTrue(
            try fixture.transferStore().allTransferRecords().isEmpty,
            "no manual archive without explicit confirmation"
        )
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == review.id }?.resolution,
            .keepSeparate
        )
    }

    func testSameTitleUnrelatedProjectIsNotBoundByTitle() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let existingID = ProjectID()
        let candidateID = ProjectID()
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [
                ProjectCatalogEntry(
                    record: ProjectRecord(id: existingID, canonicalTitle: "Friends Workflow Song", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
                ProjectCatalogEntry(
                    record: ProjectRecord(id: candidateID, canonicalTitle: "Friends Workflow Song", locations: []),
                    evidence: ProjectIdentityEvidence(folderName: "Second Project", cubaseFiles: [])
                ),
            ],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        XCTAssertEqual(viewModel.songs.count, 2, "expected fixture plus second project, got \(viewModel.songs.map(\.originalFolderName))")

        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertNil(
            presentation.song,
            "title-only overlap across two scanned songs must not bind either song"
        )
        XCTAssertNil(presentation.trigger)

        viewModel.resolvePresentedIdentityReview(as: .link)
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testPersistedReviewWithStableLocationDoesNotInventAuthorization() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let existingID = ProjectID()
        let candidateID = ProjectID()
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [
                ProjectCatalogEntry(
                    record: ProjectRecord(
                        id: existingID,
                        canonicalTitle: "Friends Workflow Song",
                        locations: [ProjectLocation(
                            rootID: fixture.activeID,
                            relativePath: fixture.project.lastPathComponent,
                            kind: .active,
                            availability: .local
                        )]
                    ),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
                ProjectCatalogEntry(
                    record: ProjectRecord(
                        id: candidateID,
                        canonicalTitle: "Elsewhere",
                        locations: [ProjectLocation(
                            rootID: fixture.activeID,
                            relativePath: "Elsewhere",
                            kind: .active,
                            availability: .local
                        )]
                    ),
                    evidence: ProjectIdentityEvidence(folderName: "Elsewhere", cubaseFiles: [])
                ),
            ],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let stable = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.song?.id, stable.id, "stable location/id must resolve the scanned song")
        XCTAssertNil(presentation.trigger, "persisted review carries no authorization even when stable")
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)
        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(
            viewModel.pendingArchiveConfirmation,
            "stable persisted resolution alone must not invent Archive Now/Done authorization"
        )
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testFailedIdentityResolutionDoesNotTriggerArchiveOrConfirmation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let review = ProjectIdentityReview(
            existingProjectID: ProjectID(),
            candidateProjectID: ProjectID(),
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()

        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.title, "this project")
        XCTAssertNil(presentation.song, "unknown IDs are failed resolution, never a title match")
        XCTAssertNil(presentation.trigger)

        viewModel.resolvePresentedIdentityReview(as: .link)
        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(viewModel.pendingArchiveConfirmation, "failed resolution must not trigger a new archive")
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testPersistedReviewNoIntentReportsSavedButUnavailable() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let review = ProjectIdentityReview(
            existingProjectID: ProjectID(),
            candidateProjectID: ProjectID(),
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()

        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertNil(presentation.trigger, "persisted review carries no authorization")
        XCTAssertNil(presentation.song, "unknown IDs never bind by title")

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(viewModel.pendingArchiveConfirmation, "persisted review must not invent confirmation")
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == review.id }?.resolution,
            .keepSeparate
        )
        let status = try XCTUnwrap(viewModel.statusMessage, "saved-but-unavailable needs actionable status")
        XCTAssertTrue(status.contains("Identity choice saved"))
        XCTAssertTrue(status.contains("changed or is unavailable"))
        XCTAssertTrue(status.contains("Refresh"))
        XCTAssertTrue(status.contains("Nothing was archived"))
    }

    func testCurrentIntentLostBindingReportsSavedButUnavailable() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let first = ProjectID(rawValue: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!)
        let second = ProjectID(rawValue: UUID(uuidString: "abababab-abab-4aba-8aba-abababababab")!)
        try seedDuplicateCatalogEntries(on: fixture, projectIDs: [first, second])

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.archiveInProjectVault(song, trigger: .manual)
        try await waitUntil {
            viewModel.identityReviewPresentation != nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.trigger, .manual)

        // Project disappears before the decision: stable binding is lost.
        try FileManager.default.removeItem(at: fixture.project)

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(viewModel.pendingArchiveConfirmation, "lost binding must not earn fresh confirmation or auto-archive")
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == presentation.review.id }?.resolution,
            .keepSeparate
        )
        let status = try XCTUnwrap(viewModel.statusMessage, "lost binding needs actionable status")
        XCTAssertTrue(status.contains("Identity choice saved"))
        XCTAssertTrue(status.contains("changed or is unavailable"))
        XCTAssertTrue(status.contains("Refresh"))
        XCTAssertTrue(status.contains("Nothing was archived"))
    }

    func testExplicitWorkflowDoneResolutionPresentsFreshDoneConfirmation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let first = ProjectID(rawValue: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
        let second = ProjectID(rawValue: UUID(uuidString: "44444444-4444-4433-8433-444444444444")!)
        try seedDuplicateCatalogEntries(on: fixture, projectIDs: [first, second])

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        XCTAssertNotEqual(song.workflowStatus, .done)

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .workflowDone)

        viewModel.confirmPendingArchive()
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done)
        try await waitUntil {
            viewModel.identityReviewPresentation != nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertEqual(presentation.trigger, .workflowDone)
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done)

        viewModel.resolvePresentedIdentityReview(as: .link)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        XCTAssertNil(viewModel.identityReviewPresentation)
        let confirmation = try XCTUnwrap(
            viewModel.pendingArchiveConfirmation,
            "explicit Done flow requires fresh Done confirmation after identity resolution"
        )
        _ = try XCTUnwrap(confirmation.authorization, "V3 fresh Done confirmation must carry its captured token")
        XCTAssertEqual(confirmation.trigger, .workflowDone)
        XCTAssertEqual(confirmation.songID, song.id)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)

        viewModel.confirmPendingArchive()
        try await waitUntil {
            viewModel.pendingArchiveConfirmation == nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done)
        XCTAssertFalse(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testResolvePersistenceFailureStaysVisibleAndQueuesNothing() async throws {
        let review = ProjectIdentityReview(
            existingProjectID: ProjectID(),
            candidateProjectID: ProjectID(),
            reason: "Conflicting fixture evidence"
        )
        let viewModel = ProjectIdentityReviewViewModel(reviews: [review])
        viewModel.persistenceOverride = { _, _ in throw NSError(domain: "nmh-test", code: 1) }

        XCTAssertFalse(viewModel.resolve(review.id, as: .keepSeparate))
        XCTAssertEqual(viewModel.pendingReviews.map(\.id), [review.id])

        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let first = ProjectID(rawValue: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
        let second = ProjectID(rawValue: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!)
        try seedDuplicateCatalogEntries(on: fixture, projectIDs: [first, second])

        let browser = fixture.viewModel(runtime: try fixture.runtime())
        await browser.scan()
        let song = try XCTUnwrap(browser.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        browser.archiveInProjectVault(song, trigger: .manual)
        try await waitUntil {
            browser.identityReviewPresentation != nil && browser.projectVaultBusySongIDs.isEmpty
        }
        let presentedID = try XCTUnwrap(browser.identityReviewPresentation?.review.id)
        browser.identityReviewViewModel.persistenceOverride = { _, _ in throw NSError(domain: "nmh-test", code: 1) }

        browser.resolvePresentedIdentityReview(as: .keepSeparate)

        XCTAssertNotNil(browser.identityReviewPresentation, "persistence failure must stay visible")
        XCTAssertEqual(browser.identityReviewViewModel.pendingReviews.map(\.id), [presentedID])
        XCTAssertNil(browser.pendingArchiveConfirmation)
        XCTAssertTrue(browser.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(browser.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(browser.projectVaultActiveOperation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)

        browser.identityReviewViewModel.persistenceOverride = nil
        browser.resolvePresentedIdentityReview(as: .keepSeparate)
        try await waitUntil { browser.pendingArchiveConfirmation != nil }

        XCTAssertNil(browser.identityReviewPresentation)
        XCTAssertEqual(browser.pendingArchiveConfirmation?.trigger, .manual)
        XCTAssertEqual(browser.pendingArchiveConfirmation?.songID, song.id)
        XCTAssertNotNil(browser.pendingArchiveConfirmation?.authorization)
        browser.cancelPendingArchive()
    }

    func testBackupCopyResolutionPreservesCopyOnlyScope() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let first = ProjectID(rawValue: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!)
        let second = ProjectID(rawValue: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)
        try seedDuplicateCatalogEntries(on: fixture, projectIDs: [first, second])

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.archiveInProjectVault(song, trigger: .backupCopy)
        try await waitUntil {
            viewModel.identityReviewPresentation != nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        XCTAssertEqual(viewModel.identityReviewPresentation?.trigger, .backupCopy)

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(
            viewModel.pendingArchiveConfirmation,
            "backup-copy resolution must not escalate to an Archive Now confirmation"
        )
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(viewModel.statusMessage?.contains("Create Backup Copy") == true)
        XCTAssertTrue(viewModel.statusMessage?.contains("Active project stays") == true)

        let current = try XCTUnwrap(viewModel.songs.first { $0.id == song.id })
        XCTAssertTrue(viewModel.canArchiveInProjectVault(current))
        viewModel.archiveInProjectVault(current, trigger: .backupCopy)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertFalse(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testStaleFallbackRootDoesNotAuthorizeAnotherProject() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-stale-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let elsewhereBookmark = try elsewhere.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let staleRootID = UUID()
        let activeURL = fixture.active
        try fixture.settingsStore.updateSettings { settings in
            settings.musicRoots.append(StoredMusicRoot(
                id: staleRootID,
                role: .scanOnly,
                displayName: activeURL.lastPathComponent,
                pathFallback: activeURL.path,
                securityScopedBookmark: elsewhereBookmark
            ))
        }
        let existingID = ProjectID()
        let candidateID = ProjectID()
        let review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
        )
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: [
                ProjectCatalogEntry(
                    record: ProjectRecord(
                        id: existingID,
                        canonicalTitle: "Friends Workflow Song",
                        locations: [ProjectLocation(
                            rootID: staleRootID,
                            relativePath: fixture.project.lastPathComponent,
                            kind: .active,
                            availability: .local
                        )]
                    ),
                    evidence: ProjectIdentityEvidence(folderName: "Friends Workflow Song", cubaseFiles: [])
                ),
                ProjectCatalogEntry(
                    record: ProjectRecord(
                        id: candidateID,
                        canonicalTitle: "Elsewhere",
                        locations: [ProjectLocation(
                            rootID: staleRootID,
                            relativePath: "Elsewhere",
                            kind: .active,
                            availability: .local
                        )]
                    ),
                    evidence: ProjectIdentityEvidence(folderName: "Elsewhere", cubaseFiles: [])
                ),
            ],
            reviews: [review],
            metadataMigrations: [:]
        ))

        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        XCTAssertNotNil(
            viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent },
            "fixture song must be scanned so the nil binding is meaningful"
        )
        viewModel.presentPendingIdentityReviewsIfNeeded()
        let presentation = try XCTUnwrap(viewModel.identityReviewPresentation)
        XCTAssertNil(
            presentation.song,
            "stale fallback path must not authorize another project when the bookmark resolves elsewhere"
        )
        XCTAssertNil(presentation.trigger)

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)
        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == review.id }?.resolution,
            .keepSeparate
        )
    }

    private func seedDuplicateCatalogEntries(on fixture: FriendsWorkflowFixture, projectIDs: [ProjectID]) throws {
        let cpr = fixture.project.appendingPathComponent("Friends Workflow Song.cpr")
        let attributes = try FileManager.default.attributesOfItem(atPath: cpr.path)
        let modifiedAt = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
        let evidence = ProjectIdentityEvidence(
            folderName: fixture.project.lastPathComponent,
            cubaseFiles: [ProjectFileIdentity(
                name: "Friends Workflow Song.cpr",
                byteCount: byteCount,
                modifiedAt: modifiedAt
            )]
        )
        let entries = projectIDs.map { projectID in
            ProjectCatalogEntry(
                record: ProjectRecord(
                    id: projectID,
                    canonicalTitle: "Friends Workflow Song",
                    locations: [ProjectLocation(
                        rootID: fixture.activeID,
                        relativePath: fixture.project.lastPathComponent,
                        kind: .active,
                        availability: .local
                    )],
                    workflowState: .prod
                ),
                evidence: evidence
            )
        }
        try fixture.catalogStore().apply(
            ProjectCatalogReconciliation(entries: entries, reviews: [], metadataMigrations: [:])
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for identity review UI state")
    }

    private func removeDatabase(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
