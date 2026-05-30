import AppCore
import SwiftUI

public struct ArchiveBrowserFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "archive-browser",
        displayName: "Archive Browser",
        shortLabel: "Archive",
        systemImage: "music.note.list"
    )

    private let viewModel: ArchiveBrowserViewModel

    public init(viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
    }

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(ArchiveBrowserView(context: context, viewModel: viewModel))
    }
}
