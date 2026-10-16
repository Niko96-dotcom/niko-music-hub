import AppCore
import Foundation

public final class DemucsMLXBackend: StemSeparationBackend, @unchecked Sendable {
    private let settingsProvider: @Sendable () throws -> HelperToolSettings
    private let healthChecker: DemucsMLXHealthChecker
    private let commandBuilder: DemucsMLXCommandBuilder
    private let runner: any ExternalProcessRunning
    private let progressParser: DemucsMLXProgressParser
    private let scanner: StemOutputScanner

    private let lock = NSLock()
    private var currentTask: Task<StemSeparationResult, Never>?
    private var currentTaskID: UUID?
    private var cancellationRequestedTaskID: UUID?
    private var lastConfiguredDemucsURL: URL?

    public init(
        settings: HelperToolSettings = HelperToolSettings(),
        healthChecker: DemucsMLXHealthChecker = DemucsMLXHealthChecker(),
        commandBuilder: DemucsMLXCommandBuilder = DemucsMLXCommandBuilder(),
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        progressParser: DemucsMLXProgressParser = DemucsMLXProgressParser(),
        scanner: StemOutputScanner = StemOutputScanner(),
        settingsProvider: (@Sendable () throws -> HelperToolSettings)? = nil
    ) {
        let captured = settings
        self.settingsProvider = settingsProvider ?? { captured }
        self.healthChecker = healthChecker
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.progressParser = progressParser
        self.scanner = scanner
    }

    public var supportedPresets: [StemSeparationPreset] {
        StemSeparationPreset.allCases
    }

    public var configuredDemucsURL: URL? {
        lock.withLock { lastConfiguredDemucsURL }
    }

    public func health(settings: HelperToolSettings) async -> StemBackendHealth {
        await healthChecker.availability(settings: settings)
    }

    public func separate(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult {
        let taskID = UUID()
        let didReserveOperation = lock.withLock { () -> Bool in
            guard currentTaskID == nil else { return false }
            currentTaskID = taskID
            return true
        }
        guard didReserveOperation else {
            return .failed(message: "A stem separation is already running.")
        }

        let parentWasAlreadyCancelled = Task.isCancelled
        let work: Task<StemSeparationResult, Never> = Task {
            guard !parentWasAlreadyCancelled else { return .canceled }
            return await self.performSeparation(request: request, onProgress: onProgress)
        }
        let cancellationWasRequested = lock.withLock { () -> Bool in
            guard currentTaskID == taskID else { return true }
            currentTask = work
            return cancellationRequestedTaskID == taskID
        }
        if parentWasAlreadyCancelled || cancellationWasRequested {
            work.cancel()
        }
        return await withTaskCancellationHandler(operation: {
            defer { self.clearCurrentTask(id: taskID) }
            return await work.value
        }, onCancel: {
            // `Task {}` is unstructured, so explicitly forward job-task cancellation
            // to the task awaiting the process. FoundationExternalProcessRunner then
            // terminates the helper's dedicated process group.
            work.cancel()
        })
    }

    private func performSeparation(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult {
        guard !Task.isCancelled else { return .canceled }
        // Unreadable settings must not fall back to default helper paths.
        let helperSettings: HelperToolSettings
        do {
            helperSettings = try settingsProvider()
        } catch {
            return .failed(message: StemSeparationHelperCopy.settingsUnreadable)
        }
        lock.withLock { lastConfiguredDemucsURL = helperSettings.demucsMlx }
        let processRequest: ExternalProcessRequest
        do {
            processRequest = try commandBuilder.buildRequest(
                backendRequest: request,
                settings: helperSettings
            )
        } catch DemucsMLXCommandBuilderError.missingExecutable {
            return .failed(message: StemSeparationHelperCopy.missingBody, reason: .helperUnavailable)
        } catch {
            return .failed(message: StemSeparationHelperCopy.missingBody, reason: .helperUnavailable)
        }

        let startTime = Date()
        let elapsedFormatter: @Sendable (TimeInterval) -> String = { interval in
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return String(format: "%d:%02d elapsed", minutes, seconds)
        }

        let tracker = DemucsProgressTracker()
        let progressHandler: @Sendable (Double, String?) -> Void = { progress, message in
            var parts: [String] = []
            if let message {
                parts.append(message)
            }
            parts.append(elapsedFormatter(Date().timeIntervalSince(startTime)))
            let combined = parts.joined(separator: " | ")
            onProgress(progress, combined)
        }

        do {
            let result: ExternalProcessResult
            if let streamingRunner = runner as? any StreamingExternalProcessRunning {
                result = try await streamingRunner.run(
                    processRequest,
                    onStandardOutput: { [weak self] chunk in
                        self?.handleChunk(chunk, tracker: tracker, progressHandler: progressHandler)
                    },
                    onStandardError: { [weak self] chunk in
                        self?.handleChunk(chunk, tracker: tracker, progressHandler: progressHandler)
                    }
                )
            } else {
                result = try await runner.run(processRequest)
            }

            try Task.checkCancellation()

            guard result.exitCode == 0 else {
                let summary = "Stem separation failed (demucs-mlx exit code \(result.exitCode))"
                guard let cause = failureCause(from: result.standardError) else {
                    return .failed(message: summary + ".")
                }
                return .failed(message: "\(summary): \(cause)")
            }

            let outputFolderURL = resolvedOutputFolderURL(for: request)
            switch scanner.scan(outputFolderURL: outputFolderURL, expectedRoles: request.preset.expectedStemRoles) {
            case let .failed(message):
                return .failed(message: message)
            case .success(let stems):
                return .success(outputFolderURL: outputFolderURL, stems: stems)
            }
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(message: "Process error: \(error.localizedDescription)")
        }
    }

    /// The last non-progress stderr line names the cause (for example the final
    /// traceback line); the rest of the terminal output never becomes UI copy.
    private func failureCause(from standardError: String) -> String? {
        let lines = standardError.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        for raw in lines.reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, progressParser.parse(line: line) == nil else { continue }
            return line.count > 200 ? String(line.prefix(200)) + "…" : line
        }
        return nil
    }

    private func resolvedOutputFolderURL(for request: StemSeparationBackendRequest) -> URL {
        let direct = request.outputFolderURL
        let trackFolder = direct
            .appendingPathComponent(request.inputURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        let nested = direct
            .appendingPathComponent(request.preset.demucsModelID, isDirectory: true)
            .appendingPathComponent(request.inputURL.deletingPathExtension().lastPathComponent, isDirectory: true)

        if case .success = scanner.scan(outputFolderURL: direct, expectedRoles: request.preset.expectedStemRoles) {
            return direct
        }
        if case .success = scanner.scan(outputFolderURL: trackFolder, expectedRoles: request.preset.expectedStemRoles) {
            return trackFolder
        }
        if case .success = scanner.scan(outputFolderURL: nested, expectedRoles: request.preset.expectedStemRoles) {
            return nested
        }
        return direct
    }

    public func cancel() {
        let task = lock.withLock { () -> Task<StemSeparationResult, Never>? in
            guard let currentTaskID else { return nil }
            cancellationRequestedTaskID = currentTaskID
            return currentTask
        }
        task?.cancel()
    }

    private func clearCurrentTask(id: UUID) {
        lock.withLock {
            guard currentTaskID == id else { return }
            currentTask = nil
            currentTaskID = nil
            cancellationRequestedTaskID = nil
        }
    }

    private func handleChunk(
        _ chunk: String,
        tracker: DemucsProgressTracker,
        progressHandler: @escaping @Sendable (Double, String?) -> Void
    ) {
        let pieces = chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        for raw in pieces {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let parsed = progressParser.parse(line: String(trimmed)) else { continue }
            let reported = tracker.next(for: parsed.progress, message: parsed.message)
            progressHandler(reported.progress, reported.message)
        }
    }
}

/// Progress never moves backwards within one phase. Model download and loading
/// are their own phases, so a finished download does not pin separation at 100%.
private final class DemucsProgressTracker: @unchecked Sendable {
    private static let downloading = "Downloading model…"
    private static let loading = "Loading model…"
    private static let separating = "Separating stems…"

    private let lock = NSLock()
    private var phase: String?
    private var maxReported: Double = 0

    func next(for parsed: Double?, message: String?) -> (progress: Double, message: String?) {
        lock.withLock {
            var message = message
            if phase == Self.downloading, parsed != nil, message == Self.separating {
                // Bare percentages after "Downloading" belong to the download until a
                // lower value starts the next progress bar.
                if let parsed, parsed < maxReported {
                    message = Self.separating
                } else {
                    message = Self.downloading
                }
            }
            if message != phase,
               message == Self.downloading || message == Self.loading || phase == Self.downloading {
                maxReported = 0
            }
            if let message { phase = message }
            if let parsed {
                maxReported = max(parsed, maxReported)
            }
            return (maxReported, message)
        }
    }
}
