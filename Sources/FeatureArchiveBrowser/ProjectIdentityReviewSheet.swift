import AppCore
import NikoMusicCore
import SwiftUI

enum ProjectIdentityReviewCopy: Sendable {
    static let sheetTitle = "Review Duplicate Project"
    static let keepSeparate = "Keep Separate"
    static let link = "Link"
    static let cancel = "Cancel"

    static func message(title: String, reason: String) -> String {
        "Project Vault cannot tell whether “\(title)” is the same project as an existing catalog entry. \(reason) Choose Link if these are the same project. Choose Keep Separate if they are different projects. Nothing is archived until you choose."
    }
}

struct ProjectIdentityReviewPresentation: Identifiable {
    var id: UUID { review.id }
    var review: ProjectIdentityReview
    var title: String
    var song: Song?
    var trigger: ProjectVaultArchiveTrigger?

    var message: String {
        ProjectIdentityReviewCopy.message(title: title, reason: review.reason)
    }
}

struct ProjectIdentityReviewSheet: View {
    let presentation: ProjectIdentityReviewPresentation
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ProjectIdentityReviewCopy.sheetTitle)
                .font(.title2)
            Text(presentation.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(ProjectIdentityReviewCopy.cancel) {
                    viewModel.cancelPresentedIdentityReview()
                }
                .keyboardShortcut(.cancelAction)
                Button(ProjectIdentityReviewCopy.link) {
                    viewModel.resolvePresentedIdentityReview(as: .link)
                }
                Button(ProjectIdentityReviewCopy.keepSeparate) {
                    viewModel.resolvePresentedIdentityReview(as: .keepSeparate)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .interactiveDismissDisabled()
    }
}
