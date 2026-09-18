import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func presentPendingIdentityReviewsIfNeeded() {
        guard identityReviewPresentation == nil else { return }
        identityReviewViewModel.reloadFromStore()
        guard let review = identityReviewViewModel.pendingReviews.first else { return }
        identityReviewPresentation = ProjectIdentityReviewPresentation(
            review: review,
            title: titleForIdentityReview(review),
            song: songForIdentityReview(review),
            trigger: .manual
        )
    }

    func beginIdentityReview(
        for song: Song,
        title: String,
        reason: String,
        trigger: ProjectVaultArchiveTrigger
    ) async {
        let review: ProjectIdentityReview
        if let pending = await projectVaultRuntime?.consumePendingIdentityReview() {
            review = pending
        } else {
            review = ProjectIdentityReview(
                existingProjectID: ProjectID(),
                candidateProjectID: ProjectID(),
                reason: reason
            )
        }
        identityReviewViewModel.adopt(review)
        identityReviewPresentation = ProjectIdentityReviewPresentation(
            review: review,
            title: title,
            song: song,
            trigger: trigger
        )
    }

    func resolvePresentedIdentityReview(as resolution: ProjectIdentityReviewResolution) {
        guard let presentation = identityReviewPresentation else { return }
        identityReviewViewModel.resolve(presentation.review.id, as: resolution)
        identityReviewPresentation = nil
        if let song = presentation.song ?? songForIdentityReview(presentation.review) {
            archiveInProjectVault(song, trigger: presentation.trigger ?? .manual)
        }
    }

    func cancelPresentedIdentityReview() {
        identityReviewPresentation = nil
    }

    private func titleForIdentityReview(_ review: ProjectIdentityReview) -> String {
        if let entry = (try? projectCatalogStore?.loadEntries())?.first(where: {
            $0.record.id == review.existingProjectID
        }) {
            return entry.record.canonicalTitle
        }
        return songForIdentityReview(review)?.effectiveDisplayTitle ?? "this project"
    }

    private func songForIdentityReview(_ review: ProjectIdentityReview) -> Song? {
        guard let entries = try? projectCatalogStore?.loadEntries() else { return nil }
        let ids = [review.existingProjectID, review.candidateProjectID]
        let titles = Set(entries.compactMap { entry -> String? in
            ids.contains(entry.record.id) ? entry.record.canonicalTitle : nil
        })
        return songs.first { song in
            titles.contains(song.effectiveDisplayTitle) || titles.contains(song.originalFolderName)
        }
    }
}
