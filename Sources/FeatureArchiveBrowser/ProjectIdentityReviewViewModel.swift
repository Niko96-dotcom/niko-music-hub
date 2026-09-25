import Foundation
import NikoMusicCore

/// Small UI-facing queue for fail-closed duplicate decisions. Pending items remain separate
/// until a person explicitly chooses to link them.
///
/// Safety invariant: a persisted review authorizes nothing; resolution persists before the
/// sheet dismisses, and persistence failure keeps the review visible and retryable.
@MainActor
public final class ProjectIdentityReviewViewModel: ObservableObject {
    @Published public private(set) var reviews: [ProjectIdentityReview]
    private let catalogStore: SQLiteProjectCatalogStore?
    /// Deterministic persistence seam for tests. When set, `resolve` uses it instead of
    /// the catalog store so a failing store can be simulated without fixtures.
    var persistenceOverride: ((UUID, ProjectIdentityReviewResolution) throws -> Void)?

    public init(reviews: [ProjectIdentityReview] = [], catalogStore: SQLiteProjectCatalogStore? = nil) {
        self.catalogStore = catalogStore
        if let catalogStore, let stored = try? catalogStore.loadReviews(), !stored.isEmpty {
            self.reviews = stored
        } else {
            self.reviews = reviews
        }
    }

    public var pendingReviews: [ProjectIdentityReview] {
        reviews.filter { $0.resolution == .pending }
    }

    public func reloadFromStore() {
        guard let catalogStore, let stored = try? catalogStore.loadReviews() else { return }
        reviews = stored
    }

    public func adopt(_ review: ProjectIdentityReview) {
        if let index = reviews.firstIndex(where: { $0.id == review.id }) {
            reviews[index] = review
            return
        }
        let pair = Set([review.existingProjectID, review.candidateProjectID])
        if let index = reviews.firstIndex(where: {
            Set([$0.existingProjectID, $0.candidateProjectID]) == pair
        }) {
            reviews[index] = review
            return
        }
        reviews.append(review)
    }

    /// Returns true only when the resolution is persisted (or there is no store).
    /// Failure returns false and leaves the review pending so the sheet stays visible.
    ///
    /// An adopted pending review reuses the same unordered
    /// `{existingProjectID, candidateProjectID}` pair as an already-stored
    /// resolved row (duplicate-location and multiple-strong-match reviews reuse
    /// those ids). Persisting by id alone would append a second row while the
    /// older row stays first, and `ProjectCatalogReconciler` applies the first
    /// non-pending row, silently ignoring the new decision. Resolve therefore
    /// replaces every stored row with the same id or the same unordered pair
    /// with the single resolved current review, preserving unrelated reviews.
    @discardableResult
    public func resolve(_ reviewID: UUID, as resolution: ProjectIdentityReviewResolution) -> Bool {
        guard resolution != .pending,
              let index = reviews.firstIndex(where: { $0.id == reviewID }) else { return false }
        var resolved = reviews[index]
        resolved.resolution = resolution
        let pair = Set([resolved.existingProjectID, resolved.candidateProjectID])
        if let persistenceOverride {
            do {
                try persistenceOverride(reviewID, resolution)
            } catch {
                return false
            }
        } else if let catalogStore {
            do {
                let persisted = try catalogStore.loadReviews()
                let preserved = persisted.filter { existing in
                    existing.id != reviewID
                        && Set([existing.existingProjectID, existing.candidateProjectID]) != pair
                }
                var next = preserved
                next.append(resolved)
                try catalogStore.apply(ProjectCatalogReconciliation(
                    entries: try catalogStore.loadEntries(),
                    reviews: next,
                    metadataMigrations: [:]
                ))
            } catch {
                return false
            }
        }
        reviews = reviews.filter { existing in
            if existing.id == reviewID { return true }
            return Set([existing.existingProjectID, existing.candidateProjectID]) != pair
        }
        if let finalIndex = reviews.firstIndex(where: { $0.id == reviewID }) {
            reviews[finalIndex] = resolved
        } else {
            reviews.append(resolved)
        }
        return true
    }
}
