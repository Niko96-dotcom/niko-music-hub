import Foundation

final class YtDlpOutputCollector: @unchecked Sendable {
    private let outputDirectory: URL
    private let fileManager: FileManager
    private let progressHandler: @Sendable (String) -> Void
    private let onActivity: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var pending = ""
    private var accumulatedOutput = ""
    private var candidatePaths: [String] = []

    init(
        outputDirectory: URL,
        fileManager: FileManager,
        progressHandler: @escaping @Sendable (String) -> Void,
        onActivity: (@Sendable () -> Void)? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
        self.progressHandler = progressHandler
        self.onActivity = onActivity
    }

    func consume(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        onActivity?()
        let lines = lock.withLock {
            accumulatedOutput += chunk
            pending += chunk
            return drainCompleteLines()
        }
        for line in lines {
            process(line)
        }
    }

    func finish() -> [URL] {
        let finalLines = lock.withLock {
            let remaining = pending
            pending = ""
            return remaining.isEmpty ? [] : [remaining]
        }
        for line in finalLines {
            process(line)
        }

        reparseAccumulatedOutput()

        return lock.withLock {
            var resolved: [URL] = []
            for path in candidatePaths {
                for url in urls(for: path) where !resolved.contains(url) {
                    if fileManager.fileExists(atPath: url.path) {
                        resolved.append(url)
                        break
                    }
                }
            }
            return resolved
        }
    }

    private func process(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onActivity?()
        progressHandler(trimmed)
        let paths = YtDlpDownloader.outputPathCandidates(from: trimmed)
        guard !paths.isEmpty else { return }
        lock.withLock {
            for path in paths where !candidatePaths.contains(path) {
                candidatePaths.append(path)
            }
        }
    }

    private func reparseAccumulatedOutput() {
        let snapshot = lock.withLock { accumulatedOutput }
        let lines = snapshot.split(whereSeparator: \.isNewline).map(String.init)
        var tail = ""
        if !snapshot.isEmpty, !snapshot.hasSuffix("\n") {
            tail = String(lines.last ?? "")
        }
        let completeLines = tail.isEmpty ? lines : Array(lines.dropLast())

        for line in completeLines {
            let paths = YtDlpDownloader.outputPathCandidates(from: line)
            guard !paths.isEmpty else { continue }
            lock.withLock {
                for path in paths where !candidatePaths.contains(path) {
                    candidatePaths.append(path)
                }
            }
        }

        if !tail.isEmpty {
            let paths = YtDlpDownloader.outputPathCandidates(from: tail)
            guard !paths.isEmpty else { return }
            lock.withLock {
                for path in paths where !candidatePaths.contains(path) {
                    candidatePaths.append(path)
                }
            }
        }
    }

    private func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let newline = pending.firstIndex(where: \.isNewline) {
            let line = String(pending[..<newline])
            lines.append(line)
            pending.removeSubrange(...newline)
        }
        return lines
    }

    private func urls(for path: String) -> [URL] {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return [URL(fileURLWithPath: expanded)]
        }
        return [
            outputDirectory.appendingPathComponent(path),
            URL(fileURLWithPath: path),
        ]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
