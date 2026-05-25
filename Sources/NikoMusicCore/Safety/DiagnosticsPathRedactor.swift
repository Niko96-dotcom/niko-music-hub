import Foundation

public enum DiagnosticsPathRedactor {
    public static func redact(_ path: String, homeDirectory: String? = nil) -> String {
        let home = homeDirectory ?? NSHomeDirectory()
        let standardizedHome = (home as NSString).standardizingPath
        let standardizedPath = (path as NSString).standardizingPath
        guard standardizedPath.hasPrefix(standardizedHome) else { return path }
        let suffix = standardizedPath.dropFirst(standardizedHome.count)
        if suffix.hasPrefix("/") {
            return "~" + suffix
        }
        if suffix.isEmpty {
            return "~"
        }
        return "~/" + suffix
    }
}
