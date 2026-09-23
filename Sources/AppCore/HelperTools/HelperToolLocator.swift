import Foundation

public enum HelperTool: String, CaseIterable, Sendable {
    case ffmpeg
    case ffprobe
    case ytDlp = "yt-dlp"
    case demucsMlx = "demucs-mlx"

    public var executableName: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .ffmpeg:
            "FFmpeg"
        case .ffprobe:
            "ffprobe"
        case .ytDlp:
            "yt-dlp"
        case .demucsMlx:
            "demucs-mlx"
        }
    }

    public func configuredURL(in settings: HelperToolSettings) -> URL? {
        switch self {
        case .ffmpeg:
            settings.ffmpeg
        case .ffprobe:
            settings.ffprobe
        case .ytDlp:
            settings.ytDlp
        case .demucsMlx:
            settings.demucsMlx
        }
    }
}

public struct HelperToolLocator: Sendable {
    public static let toolsDirectoryEnvironmentKey = "NIKO_MUSIC_HUB_TOOLS_DIR"
    public static let ignoreSystemHelpersEnvironmentKey = "NIKO_MUSIC_HUB_IGNORE_SYSTEM_HELPERS"

    public let managedRoot: URL
    public let systemDirectories: [URL]
    private let isExecutable: @Sendable (String) -> Bool

    public var managedBinDirectory: URL {
        managedRoot.appendingPathComponent("bin", isDirectory: true)
    }

    public init(
        managedRoot: URL,
        systemDirectories: [URL],
        isExecutable: @escaping @Sendable (String) -> Bool = { path in
            FileManager().isExecutableFile(atPath: path)
        }
    ) {
        self.managedRoot = managedRoot
        self.systemDirectories = systemDirectories
        self.isExecutable = isExecutable
    }

    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HelperToolLocator {
        let managedRoot: URL
        if let override = environment[toolsDirectoryEnvironmentKey], !override.isEmpty {
            managedRoot = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            managedRoot = homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Niko Music Hub", isDirectory: true)
                .appendingPathComponent("Tools", isDirectory: true)
        }

        let systemDirectories: [URL]
        if environment[ignoreSystemHelpersEnvironmentKey] == "1" {
            systemDirectories = []
        } else {
            systemDirectories = [
                URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
                URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
                URL(fileURLWithPath: "/opt/local/bin", isDirectory: true),
                homeDirectory
                    .appendingPathComponent(".local", isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true),
            ]
        }

        return HelperToolLocator(managedRoot: managedRoot, systemDirectories: systemDirectories)
    }

    public var candidateDirectories: [URL] {
        Self.deduplicated([managedBinDirectory] + systemDirectories)
    }

    public func resolve(_ tool: HelperTool, settings: HelperToolSettings) -> URL? {
        if let configured = tool.configuredURL(in: settings), isExecutable(configured.path) {
            return configured
        }
        for directory in candidateDirectories {
            let candidate = directory.appendingPathComponent(tool.executableName, isDirectory: false)
            if isExecutable(candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func managedExecutableURL(for tool: HelperTool) -> URL {
        managedBinDirectory.appendingPathComponent(tool.executableName, isDirectory: false)
    }

    public func isManaged(_ url: URL) -> Bool {
        let root = managedRoot.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        if candidate == root {
            return true
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    public func searchDirectories(settings: HelperToolSettings) -> [URL] {
        var ordered: [URL] = []
        let configuredInOrder: [URL?] = [
            settings.ytDlp,
            settings.ffmpeg,
            settings.ffprobe,
            settings.demucsMlx,
        ]
        for url in configuredInOrder {
            guard let url, isExecutable(url.path) else { continue }
            ordered.append(url.deletingLastPathComponent())
        }
        ordered += candidateDirectories
        return Self.deduplicated(ordered)
    }

    public func processEnvironment(
        settings: HelperToolSettings,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let searchPaths = searchDirectories(settings: settings).map(\.path)
        let basePathValue = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let baseEntries = basePathValue
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
        var seen = Set<String>(searchPaths)
        var combined = searchPaths
        for entry in baseEntries where !seen.contains(entry) {
            combined.append(entry)
            seen.insert(entry)
        }
        var result = base
        result["PATH"] = combined.joined(separator: ":")
        return result
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []
        ordered.reserveCapacity(urls.count)
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                ordered.append(url)
            }
        }
        return ordered
    }
}
