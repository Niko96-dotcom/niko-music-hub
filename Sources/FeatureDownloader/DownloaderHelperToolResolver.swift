import AppCore
import Foundation

enum DownloaderHelperToolResolver {
    static let commonHelperDirectories: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/local/bin", isDirectory: true)
    ]

    static func ffmpegLocationURL(
        settings: HelperToolSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        if let configured = settings.ffmpeg, fileExists(configured.path) {
            return configured.deletingLastPathComponent()
        }

        return commonHelperDirectories.first { directory in
            fileExists(directory.appendingPathComponent("ffmpeg").path)
        }
    }

    static func helperSearchDirectories(
        settings: HelperToolSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [URL] {
        var directories: [URL] = []
        appendParentDirectory(of: settings.ytDlp, to: &directories, fileExists: fileExists)
        appendParentDirectory(of: settings.ffmpeg, to: &directories, fileExists: fileExists)
        appendParentDirectory(of: settings.ffprobe, to: &directories, fileExists: fileExists)
        for directory in commonHelperDirectories {
            appendUnique(directory, to: &directories)
        }
        return directories
    }

    static func processEnvironment(
        helperSearchDirectories: [URL],
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String]? {
        let directories = unique(helperSearchDirectories)
        guard !directories.isEmpty else { return nil }

        var environment = base
        let existingPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathParts = directories.map(\.path)
        for existing in existingPath.split(separator: ":").map(String.init) where !pathParts.contains(existing) {
            pathParts.append(existing)
        }
        environment["PATH"] = pathParts.joined(separator: ":")
        return environment
    }

    static func processEnvironment(
        settings: HelperToolSettings,
        base: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String: String]? {
        processEnvironment(
            helperSearchDirectories: helperSearchDirectories(settings: settings, fileExists: fileExists),
            base: base
        )
    }

    private static func appendParentDirectory(
        of executableURL: URL?,
        to directories: inout [URL],
        fileExists: (String) -> Bool
    ) {
        guard let executableURL, fileExists(executableURL.path) else { return }
        appendUnique(executableURL.deletingLastPathComponent(), to: &directories)
    }

    private static func appendUnique(_ directory: URL, to directories: inout [URL]) {
        let standardized = directory.standardizedFileURL
        guard !directories.contains(where: { $0.standardizedFileURL.path == standardized.path }) else { return }
        directories.append(standardized)
    }

    private static func unique(_ directories: [URL]) -> [URL] {
        var resolved: [URL] = []
        for directory in directories {
            appendUnique(directory, to: &resolved)
        }
        return resolved
    }
}
