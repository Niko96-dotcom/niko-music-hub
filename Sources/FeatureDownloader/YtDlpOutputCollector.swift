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

/// One collected yt-dlp output path with its adapter-boundary provenance.
/// A path announced on an already-downloaded marker line (`--no-overwrites`
/// skip) refers to a pre-existing file; any other announced path refers to a
/// file this run wrote. Presentation policy never re-derives this.
struct YtDlpCollectedOutput: Equatable, Sendable {
    var url: URL
    var isAlreadyExisting: Bool
}

/// The process pipe a chunk came from. Raw pipe reads are not split at line
/// ends, so each stream keeps its own pending line.
enum YtDlpOutputStream: Sendable {
    case standardOutput
    case standardError
}

final class YtDlpOutputCollector: @unchecked Sendable {
    static let defaultMaximumPendingLineBytes = 16 * 1_024
    // A playlist is currently capped at 25 downloads. Leave room for several
    // yt-dlp intermediate/final-path messages per output while bounding noise.
    static let defaultMaximumCandidatePaths = 256

    /// The selected output root. Read by the adapter for post-settle salvage:
    /// the same collector is finished after thrown process/stall errors.
    let outputDirectory: URL
    private let fileManager: FileManager
    private let pathSafety: PathSafety
    private let progressHandler: @Sendable (String) -> Void
    private let onActivity: (@Sendable () -> Void)?
    private let maximumPendingLineBytes: Int
    private let maximumCandidatePaths: Int
    private let lock = NSLock()
    private var pending: [YtDlpOutputStream: String] = [:]
    private var isDiscardingOversizedLine: Set<YtDlpOutputStream> = []
    private var candidatePaths: [String] = []
    private var candidatePathSet: Set<String> = []
    private var freshCandidatePaths: Set<String> = []
    private var alreadyExistingCandidatePaths: Set<String> = []
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

    func consume(_ chunk: String, from stream: YtDlpOutputStream = .standardOutput) {
        guard !chunk.isEmpty else { return }
        onActivity?()
        lock.withLock {
            consumeLocked(chunk, from: stream)
        }
    }

    /// Processes an unterminated last line of `stream`, so the next stream's
    /// output cannot join it.
    func finishPendingLine(of stream: YtDlpOutputStream) {
        lock.withLock {
            finishPendingLineLocked(stream)
        }
    }

    func finish() throws -> [URL] {
        try finishCollecting().map(\.url)
    }

    /// Collected outputs with adapter-boundary provenance. Only existing
    /// contained paths resolve; a path is already-existing only when a skip
    /// marker was seen and no fresh-destination announcement was seen for the
    /// same normalized path (fresh wins, e.g. the same playlist video listed
    /// twice). `NIKO_MUSIC_HUB_FILE:` after_move prints are neutral and never
    /// flip provenance alone. Storage is keyed by normalized absolute path so
    /// aliases merge instead of first-path-wins; all sets stay within
    /// `maximumCandidatePaths`.
    func finishCollecting() throws -> [YtDlpCollectedOutput] {
        try lock.withLock {
            finishPendingLineLocked(.standardOutput)
            finishPendingLineLocked(.standardError)
            if didExceedCandidateLimit {
                throw YtDlpOutputCollectorError.candidateLimitExceeded(maximum: maximumCandidatePaths)
            }
            var resolved: [YtDlpCollectedOutput] = []
            for key in candidatePaths {
                let isAlreadyExisting = alreadyExistingCandidatePaths.contains(key)
                    && !freshCandidatePaths.contains(key)
                let url = URL(fileURLWithPath: key)
                if fileManager.fileExists(atPath: url.path) {
                    if pathSafety.isResolvedContained(url, in: [outputDirectory]) {
                        resolved.append(YtDlpCollectedOutput(url: url, isAlreadyExisting: isAlreadyExisting))
                    }
                }
            }
            return resolved
        }
    }

    private func consumeLocked(_ chunk: String, from stream: YtDlpOutputStream) {
        var remaining = chunk[...]
        while let newline = remaining.firstIndex(where: \.isNewline) {
            appendToPendingLineLocked(remaining[..<newline], stream: stream)
            finishPendingLineLocked(stream)
            remaining = remaining[remaining.index(after: newline)...]
        }
        appendToPendingLineLocked(remaining, stream: stream)
    }

    private func appendToPendingLineLocked(_ fragment: Substring, stream: YtDlpOutputStream) {
        guard !isDiscardingOversizedLine.contains(stream) else { return }
        let current = pending[stream, default: ""]
        let availableBytes = maximumPendingLineBytes - current.utf8.count
        guard fragment.utf8.count <= availableBytes else {
            pending[stream] = nil
            isDiscardingOversizedLine.insert(stream)
            return
        }
        pending[stream, default: ""].append(contentsOf: fragment)
    }

    private func finishPendingLineLocked(_ stream: YtDlpOutputStream) {
        let line = pending.removeValue(forKey: stream) ?? ""
        let wasDiscarding = isDiscardingOversizedLine.remove(stream) != nil
        guard !wasDiscarding, !line.isEmpty else { return }
        processLocked(line)
    }

    private func processLocked(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onActivity?()
        progressHandler(trimmed)
        let paths = YtDlpDownloader.outputPathCandidates(from: trimmed)
        guard !paths.isEmpty else { return }
        // Adapter-boundary provenance: only the skip-marker shape marks a
        // path as pre-existing; only Destination/Merger/MoveFiles shapes mark
        // fresh. NIKO_MUSIC_HUB_FILE final-path prints are neutral. Fresh
        // always wins at merge time. All storage is normalized and bounded.
        let isSkipMarkerLine = YtDlpDownloader.isAlreadyDownloadedMarkerLine(trimmed)
        let isFreshLine = YtDlpDownloader.isFreshDestinationLine(trimmed)
        var reachedCandidateLimit = false
        for rawPath in paths {
            guard let key = normalizedCandidateKey(for: rawPath) else { continue }
            if !candidatePathSet.contains(key) {
                guard candidatePaths.count < maximumCandidatePaths else {
                    reachedCandidateLimit = true
                    continue
                }
                candidatePathSet.insert(key)
                candidatePaths.append(key)
            }
            if isSkipMarkerLine {
                alreadyExistingCandidatePaths.insert(key)
            } else if isFreshLine {
                freshCandidatePaths.insert(key)
            }
        }
        if reachedCandidateLimit, !didReportCandidateLimit {
            didReportCandidateLimit = true
            didExceedCandidateLimit = true
            progressHandler("Output path detection limit reached; additional paths were ignored.")
        }
    }

    /// Normalized absolute key for bounded dedup. Relative paths resolve only
    /// beneath the selected output directory (no process-CWD fallback).
    /// Tilde paths are rejected outright (nil). Standardizes `..`/`.`
    /// so aliases merge; containment itself is checked in `finishCollecting`
    /// after existence, against the resolved output directory.
    private func normalizedCandidateKey(for path: String) -> String? {
        guard !path.isEmpty, !path.hasPrefix("~") else { return nil }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        } else {
            return outputDirectory.appendingPathComponent(path).standardizedFileURL.path
        }
    }
}
