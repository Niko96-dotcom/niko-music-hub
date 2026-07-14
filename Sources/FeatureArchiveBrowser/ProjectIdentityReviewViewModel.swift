import Foundation
import NikoMusicCore

/// Small UI-facing queue for fail-closed duplicate decisions. Pending items remain separate
/// until a person explicitly chooses to link them.
@MainActor
public final class ProjectIdentityReviewViewModel: ObservableObject {
    @Published public private(set) var reviews: [ProjectIdentityReview]

    public init(reviews: [ProjectIdentityReview]) {
        self.reviews = reviews
    }

    public var pendingReviews: [ProjectIdentityReview] {
        reviews.filter { $0.resolution == .pending }
    }

    public func resolve(_ reviewID: UUID, as resolution: ProjectIdentityReviewResolution) {
        guard resolution != .pending,
              let index = reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        reviews[index].resolution = resolution
    }
}
