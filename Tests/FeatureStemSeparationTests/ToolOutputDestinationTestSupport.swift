import AppCore
import Foundation

extension ToolOutputDestination {
    /// A destination whose settings name no music roots, so nothing is refused.
    /// Only for tests that write into a temporary folder.
    static func noProtectedRoots(at folder: URL) -> ToolOutputDestination {
        ToolOutputDestination(settings: AppSettings(outputFolder: StoredFolderLocation(url: folder)))
    }

    /// A destination at `output` whose settings list `roots` as music roots,
    /// built the way the app builds it.
    static func protecting(_ roots: [URL], output: URL) -> ToolOutputDestination {
        var settings = AppSettings(outputFolder: StoredFolderLocation(url: output))
        settings.archiveRoots = roots.map { StoredArchiveRoot(path: $0.path) }
        return ToolOutputDestination(settings: settings)
    }
}
