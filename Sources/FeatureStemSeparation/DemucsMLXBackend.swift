import AppCore
import Foundation

public enum DemucsMLXBackendError: LocalizedError, Equatable, Sendable {
    case processLaunchFailed(String)
}

public final class DemucsMLXBackend: StemSeparationBackend, @unchecked Sendable {
    private let settings: HelperToolSettings
    private let healthChecker: DemucsMLXHealthChecker
    private let commandBuilder: DemucsMLXCommandBuilder
    private let runner: any ExternalProcessRunning
    private let progressParser: DemucsMLXProgressParser
    private let scanner: StemOutputScanner

    private let lock = NSLock()
    private var currentTask: Task<StemSeparationResult, Never>?
    private var currentProcessRequest: ExternalProcessRequest?

    public init(
        settings: HelperToolSettings = HelperToolSettings(),
        healthChecker: DemucsMLXHealthChecker = DemucsMLXHealthChecker(),
        commandBuilder: DemucsMLXCommandBuilder = DemucsMLXCommandBuilder(),
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        progressParser: DemucsMLXProgressParser = DemucsMLXProgressParser(),
        scanner: StemOutputScanner = StemOutputScanner()
    ) {
        self.settings = settings
        self.healthChecker = healthChecker
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.progressParser = progressParser
        self.scanner = scanner
    }

    public var supportedPresets: [StemSeparationPreset] {
        StemSeparationPreset.allCases
    }

    public func health(settings: HelperToolSettings) async -> StemBackendHealth {
        await healthChecker.availability(settings: settings)
    }

    public func separate(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult {
        let work = Task {
            await self.performSeparation(request: request, onProgress: onProgress)
        }
        lock.withLock {
            currentTask = work
        }
        defer {
            lock.withLock {
                currentTask = nil
                currentProcessRequest = nil
            }
        }
        return await work.value
    }

    private func performSeparation(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult {
        guard let processRequest = try? commandBuilder.buildRequest(
            backendRequest: request,
            settings: settings
        ) else {
            return .failed(message: "Could not build demucs-mlx command. Is the executable configured?")
        }

        lock.withLock {
            currentProcessRequest = processRequest
        }

        let startTime = Date()
        let elapsedFormatter: @Sendable (TimeInterval) -> String = { interval in
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return String(format: "%d:%02d elapsed", minutes, seconds)
        }

        let progressHandler: @Sendable (Double?, String?) -> Void = { progress, message in
            var parts: [String] = []
            if let message {
                parts.append(message)
            }
            if progress != nil {
                parts.append(elapsedFormatter(Date().timeIntervalSince(startTime)))
            }
            let combined = parts.isEmpty ? elapsedFormatter(Date().timeIntervalSince(startTime)) : parts.joined(separator: " | ")
            onProgress(progress ?? -1, combined)
        }

        do {
            let result: ExternalProcessResult
            if let streamingRunner = runner as? any StreamingExternalProcessRunning {
                result = try await streamingRunner.run(
                    processRequest,
                    onStandardOutput: { [weak self] line in
                        self?.handleLine(line, progressHandler: progressHandler)
                    },
                    onStandardError: { [weak self] line in
                        self?.handleLine(line, isError: true, progressHandler: progressHandler)
                    }
                )
            } else {
                result = try await runner.run(processRequest)
            }

            try Task.checkCancellation()

            guard result.exitCode == 0 else {
                let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = stderr.isEmpty
                    ? "demucs-mlx exited with code \(result.exitCode)"
                    : "demucs-mlx failed: \(stderr)"
                return .failed(message: message)
            }

            switch scanner.scan(outputFolderURL: request.outputFolderURL, expectedRoles: request.preset.expectedStemRoles) {
            case .failed(let message):
                return .failed(message: message)
            case .success(let stems):
                return .success(outputFolderURL: request.outputFolderURL, stems: stems)
            }
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(message: "Process error: \(error.localizedDescription)")
        }
    }

    public func cancel() {
        lock.withLock {
            currentTask?.cancel()
            currentTask = nil
        }
    }

    private func handleLine(
        _ line: String,
        isError: Bool = false,
        progressHandler: @escaping @Sendable (Double?, String?) -> Void
    ) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isError {
            progressHandler(nil, "stderr: \(trimmed)")
            return
        }

        if let parsed = progressParser.parse(line: trimmed) {
            progressHandler(parsed.progress, parsed.message)
        } else {
            progressHandler(nil, trimmed)
        }
    }
}
