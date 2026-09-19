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
    @discardableResult
    public func resolve(_ reviewID: UUID, as resolution: ProjectIdentityReviewResolution) -> Bool {
        guard resolution != .pending,
              let index = reviews.firstIndex(where: { $0.id == reviewID }) else { return false }
        if let persistenceOverride {
            do {
                try persistenceOverride(reviewID, resolution)
            } catch {
                return false
            }
        } else if let catalogStore {
            do {
                var persisted = try catalogStore.loadReviews()
                if let storedIndex = persisted.firstIndex(where: { $0.id == reviewID }) {
                    persisted[storedIndex].resolution = resolution
                } else {
                    var copy = reviews[index]
                    copy.resolution = resolution
                    persisted.append(copy)
                }
                try catalogStore.apply(ProjectCatalogReconciliation(
                    entries: try catalogStore.loadEntries(),
                    reviews: persisted,
                    metadataMigrations: [:]
                ))
            } catch {
                return false
            }
        }
        reviews[index].resolution = resolution
        return true
    }
}
