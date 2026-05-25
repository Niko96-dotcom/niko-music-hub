import AppCore
import SwiftUI

public struct ArchiveBrowserFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "archive-browser",
        displayName: "Archive Browser",
        shortLabel: "Archive",
        systemImage: "music.note.list"
    )

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(ArchiveBrowserView(context: context))
    }
}
