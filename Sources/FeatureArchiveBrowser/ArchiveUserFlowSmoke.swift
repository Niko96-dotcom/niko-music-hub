import AppCore
import Foundation
import NikoMusicCore

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    public let userFlow: String
    public let songCount: Int
    public let searchQuery: String
    public let searchMatchCount: Int
    public let selectedTitle: String
    public let dryRunCPRPath: String
    public let dryRunLogLine: String?
    public let writeProbeDenied: Bool
    public let archiveTreeUnchanged: Bool
    public let diagnosticsSongCount: Int
    public let diagnosticsSkippedCount: Int

    public init(
        userFlow: String,
        songCount: Int,
        searchQuery: String,
        searchMatchCount: Int,
        selectedTitle: String,
        dryRunCPRPath: String,
        dryRunLogLine: String?,
        writeProbeDenied: Bool,
        archiveTreeUnchanged: Bool,
        diagnosticsSongCount: Int,
        diagnosticsSkippedCount: Int
    ) {
        self.userFlow = userFlow
        self.songCount = songCount
        self.searchQuery = searchQuery
        self.searchMatchCount = searchMatchCount
        self.selectedTitle = selectedTitle
        self.dryRunCPRPath = dryRunCPRPath
        self.dryRunLogLine = dryRunLogLine
        self.writeProbeDenied = writeProbeDenied
        self.archiveTreeUnchanged = archiveTreeUnchanged
        self.diagnosticsSongCount = diagnosticsSongCount
        self.diagnosticsSkippedCount = diagnosticsSkippedCount
    }
}

public enum ArchiveUserFlowSmokeError: Error, Equatable, Sendable {
    case neonHookNotFound
    case missingDryRunPath
}

@MainActor
public enum ArchiveUserFlowSmoke {
    public static func run(
        fixtureRoot: URL,
        context: ToolContext
    ) throws -> ArchiveUserFlowSmokeResult {
        let policy = ReadOnlyArchivePolicy()
        let writeProbeDenied = policy.writeProbeDenied(under: fixtureRoot)
        let treeBefore = try snapshotArchiveTree(at: fixtureRoot)

        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", fixtureRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: context)
        viewModel.scanSync()

        let searchQuery = "neon hk"
        viewModel.searchQuery = searchQuery
        viewModel.applySearchFilter()

        guard let neon = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.neonHookNotFound
        }
        viewModel.selectSong(neon)
        try viewModel.openLatestCPR(for: neon)

        guard let dryRunPath = viewModel.lastDryRunLog else {
            throw ArchiveUserFlowSmokeError.missingDryRunPath
        }

        let treeAfter = try snapshotArchiveTree(at: fixtureRoot)
        let dryRunLogLine = captureDryRunLogLine(from: context)

        let diagnostics = viewModel.scanDiagnostics

        return ArchiveUserFlowSmokeResult(
            userFlow: "scan_search_open",
            songCount: viewModel.songs.count,
            searchQuery: searchQuery,
            searchMatchCount: viewModel.filteredSongs.count,
            selectedTitle: neon.displayTitle,
            dryRunCPRPath: dryRunPath,
            dryRunLogLine: dryRunLogLine,
            writeProbeDenied: writeProbeDenied,
            archiveTreeUnchanged: treeBefore == treeAfter,
            diagnosticsSongCount: diagnostics?.songCount ?? 0,
            diagnosticsSkippedCount: diagnostics?.skippedEntries.count ?? 0
        )
    }

    private static func captureDryRunLogLine(from context: ToolContext) -> String? {
        guard let capturing = context.diagnostics as? CapturingDiagnostics else {
            return nil
        }
        return capturing.lines.last { $0.contains("[dry-run] open CPR:") }
    }

    private static func snapshotArchiveTree(at root: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPrefix = root.standardizedFileURL.path + "/"
        var lines: [String] = []
        while let url = enumerator.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            let relative = String(url.path.dropFirst(rootPrefix.count))
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values.fileSize ?? 0
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            lines.append("\(relative)|\(size)|\(modified)")
        }
        return lines.sorted()
    }
}

/// Test/smoke helper that records diagnostic lines for assertions.
public final class CapturingDiagnostics: Diagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []

    public init() {}

    public func log(_ level: DiagnosticLevel, _ message: String) {
        lock.lock()
        lines.append(message)
        lock.unlock()
        print("[\(level.rawValue)] \(message)")
    }
}
