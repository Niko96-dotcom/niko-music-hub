import AppCore
import Foundation

extension ToolOutputDestination {
    /// A destination whose settings name no music roots, so nothing is refused.
    /// Only for tests that write into a temporary folder.
    static func noProtectedRoots(at folder: URL) -> ToolOutputDestination {
        ToolOutputDestination(settings: AppSettings(outputFolder: StoredFolderLocation(url: folder)))
    }
}
