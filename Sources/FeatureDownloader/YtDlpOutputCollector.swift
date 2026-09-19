import Foundation
import NikoMusicCore

enum YtDlpOutputCollectorError: LocalizedError, Equatable, Sendable {
    case candidateLimitExceeded(maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .candidateLimitExceeded(maximum):
            return "yt-dlp reported more than \(maximum) output paths. The download was not recorded as complete; reduce the playlist size and retry."
        }
    }
}

final class YtDlpOutputCollector: @unchecked Sendable {
    static let defaultMaximumPendingLineBytes = 16 * 1_024
    // A playlist is currently capped at 25 downloads. Leave room for several
    // yt-dlp intermediate/final-path messages per output while bounding noise.
    static let defaultMaximumCandidatePaths = 256

    private let outputDirectory: URL
    private let fileManager: FileManager
    private let pathSafety: PathSafety
    private let progressHandler: @Sendable (String) -> Void
    private let onActivity: (@Sendable () -> Void)?
    private let maximumPendingLineBytes: Int
    private let maximumCandidatePaths: Int
    private let lock = NSLock()
    private var pending = ""
    private var isDiscardingOversizedLine = false
    private var candidatePaths: [String] = []
    private var candidatePathSet: Set<String> = []
    private var didReportCandidateLimit = false
    private var didExceedCandidateLimit = false

    init(
        outputDirectory: URL,
        fileManager: FileManager,
        progressHandler: @escaping @Sendable (String) -> Void,
        onActivity: (@Sendable () -> Void)? = nil,
        maximumPendingLineBytes: Int = defaultMaximumPendingLineBytes,
        maximumCandidatePaths: Int = defaultMaximumCandidatePaths
    ) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
        self.pathSafety = PathSafety(fileManager: fileManager)
        self.progressHandler = progressHandler
        self.onActivity = onActivity
        self.maximumPendingLineBytes = max(1, maximumPendingLineBytes)
        self.maximumCandidatePaths = max(1, maximumCandidatePaths)
    }

    func consume(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        onActivity?()
        lock.withLock {
            consumeLocked(chunk)
        }
    }

    func finish() throws -> [URL] {
        try lock.withLock {
            finishPendingLineLocked()
            if didExceedCandidateLimit {
                throw YtDlpOutputCollectorError.candidateLimitExceeded(maximum: maximumCandidatePaths)
            }
            var resolved: [URL] = []
            for path in candidatePaths {
                for url in urls(for: path) where !resolved.contains(url) {
                    if fileManager.fileExists(atPath: url.path) {
                        if pathSafety.isResolvedContained(url, in: [outputDirectory]) {
                            resolved.append(url)
                        }
                        break
                    }
                }
            }
            return resolved
        }
    }

    private func consumeLocked(_ chunk: String) {
        var remaining = chunk[...]
        while let newline = remaining.firstIndex(where: \.isNewline) {
            appendToPendingLineLocked(remaining[..<newline])
            finishPendingLineLocked()
            remaining = remaining[remaining.index(after: newline)...]
        }
        appendToPendingLineLocked(remaining)
    }

    private func appendToPendingLineLocked(_ fragment: Substring) {
        guard !isDiscardingOversizedLine else { return }
        let availableBytes = maximumPendingLineBytes - pending.utf8.count
        guard fragment.utf8.count <= availableBytes else {
            pending = ""
            isDiscardingOversizedLine = true
            return
        }
        pending.append(contentsOf: fragment)
    }

    private func finishPendingLineLocked() {
        defer {
            pending = ""
            isDiscardingOversizedLine = false
        }
        guard !isDiscardingOversizedLine, !pending.isEmpty else { return }
        processLocked(pending)
    }

    private func processLocked(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onActivity?()
        progressHandler(trimmed)
        let paths = YtDlpDownloader.outputPathCandidates(from: trimmed)
        guard !paths.isEmpty else { return }
        var reachedCandidateLimit = false
        for path in paths where !candidatePathSet.contains(path) {
            guard candidatePaths.count < maximumCandidatePaths else {
                reachedCandidateLimit = true
                continue
            }
            candidatePathSet.insert(path)
            candidatePaths.append(path)
        }
        if reachedCandidateLimit, !didReportCandidateLimit {
            didReportCandidateLimit = true
            didExceedCandidateLimit = true
            progressHandler("Output path detection limit reached; additional paths were ignored.")
        }
    }

    private func urls(for path: String) -> [URL] {
        // Never expand `~`: tilde-based paths are rejected outright.
        guard !path.isEmpty, !path.hasPrefix("~") else { return [] }
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            // Relative paths resolve only beneath the selected output directory.
            // There is intentionally no process-CWD fallback.
            candidate = outputDirectory.appendingPathComponent(path)
        }
        // Standardize `..`/`.` here so `finish()` enforces containment on the
        // normalized, symlink-resolved location. Containment itself is checked
        // in `finish()` after existence, against the resolved output directory.
        return [candidate.standardizedFileURL]
    }
}
