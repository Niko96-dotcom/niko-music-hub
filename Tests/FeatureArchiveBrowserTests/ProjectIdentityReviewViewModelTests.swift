import AppCore
@testable import FeatureArchiveBrowser
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

        viewModel.resolve(review.id, as: .keepSeparate)

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
        viewModel.resolve(review.id, as: .keepSeparate)

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

        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)

        try await waitUntil {
            viewModel.identityReviewPresentation == nil && viewModel.projectVaultBusySongIDs.isEmpty
        }
        XCTAssertTrue(viewModel.identityReviewViewModel.pendingReviews.isEmpty)
        XCTAssertEqual(
            try fixture.catalogStore().loadReviews().first { $0.id == presentation.review.id }?.resolution,
            .keepSeparate
        )
        let transfers = try fixture.transferStore().allTransferRecords()
        XCTAssertFalse(transfers.isEmpty, viewModel.statusMessage ?? "archive retry produced no transfer")
        XCTAssertTrue(
            transfers.contains { VaultTransferOwnershipPolicy.isVerifiedTerminal($0.state) },
            viewModel.statusMessage ?? "archive retry did not finish a verified generation"
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

        viewModel.cancelPresentedIdentityReview()

        XCTAssertNil(viewModel.identityReviewPresentation)
        XCTAssertEqual(viewModel.identityReviewViewModel.pendingReviews.map(\.id), [review.id])
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
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
