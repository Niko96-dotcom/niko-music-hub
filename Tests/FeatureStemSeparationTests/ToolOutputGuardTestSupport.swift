import AppCore
import Foundation

extension ToolOutputGuard {
    /// A guard whose settings list `roots` as music roots, built the way the app builds it.
    static func protecting(_ roots: [URL]) -> ToolOutputGuard {
        var settings = AppSettings()
        settings.archiveRoots = roots.map { StoredArchiveRoot(path: $0.path) }
        return ToolOutputGuard(settings: settings)
    }
}
