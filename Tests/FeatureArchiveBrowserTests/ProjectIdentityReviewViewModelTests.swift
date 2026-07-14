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
}
