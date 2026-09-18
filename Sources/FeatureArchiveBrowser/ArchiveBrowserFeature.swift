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

    @MainActor
    public func makeTitleBarAccessory(context _: ToolContext) -> AnyView? {
        AnyView(ArchiveLayoutToggle(viewModel: viewModel))
    }
}

/// Board ⇄ list switch. Lives in the window title bar so it stays in the
/// same spot no matter which archive page is showing.
struct ArchiveLayoutToggle: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        // One button that shows the layout you would switch TO.
        HubIconButton(
            systemImage: viewModel.isListLayout ? "rectangle.split.3x1" : "list.bullet",
            accessibilityLabel: viewModel.isListLayout ? "Show board" : "Show list",
            help: viewModel.isListLayout ? "Board" : "List",
            isEnabled: viewModel.isListLayout || !viewModel.songs.isEmpty
        ) {
            viewModel.setBrowseLayout(list: !viewModel.isListLayout)
        }
    }
}
