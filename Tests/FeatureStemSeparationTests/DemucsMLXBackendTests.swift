import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct DemucsMLXBackendTests {

    @Test
    func separate_success_publishesProgressAndReturnsStems() async throws {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 0,
            outputLines: ["Loading model", "10%", "50%", "100%", "Done"],
            errorLines: ["Tracks: 25%|██ | 1/4 [00:01<00:03, 1track/s]", "unrecognized terminal chatter"],
            filesToWrite: [
                (outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8)),
                (outputFolder.appendingPathComponent("drums.wav"), Data("d".utf8)),
                (outputFolder.appendingPathComponent("bass.wav"), Data("b".utf8)),
                (outputFolder.appendingPathComponent("other.wav"), Data("o".utf8))
            ]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let progressCollector = ProgressCollector()
        let messages = MessageCollector()
        let result = await backend.separate(request: request) { progress, message in
            if let message { messages.add(message) }
            progressCollector.add(progress)
        }
        let progressValues = progressCollector.values

        guard case .success(let folder, let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(folder == outputFolder)
        #expect(stems.count == 4)
        // The fake replays all stdout before stderr, so stderr's 25% arrives after
        // 100%; progress never moves backwards, so it must not appear.
        #expect(!progressValues.contains(0.25))
        #expect(progressValues == progressValues.sorted())
        #expect(!messages.messages.contains { $0.contains("stderr:") || $0.contains("track/s") || $0.contains("chatter") })
        #expect(progressValues.contains(0.1))
        #expect(progressValues.contains(0.5))
        #expect(progressValues.contains(1.0))
    }

    @Test
    func separate_success_scansCurrentDemucsNestedOutputLayout() async throws {
        let outputFolder = makeOutputFolder()
        let inputURL = URL(fileURLWithPath: "/Users/music/input.wav")
        let nestedFolder = outputFolder.appendingPathComponent("input", isDirectory: true)
        let request = StemSeparationBackendRequest(
            inputURL: inputURL,
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 0,
            outputLines: ["Done"],
            errorLines: [],
            filesToWrite: [
                (nestedFolder.appendingPathComponent("vocals.wav"), Data("v".utf8)),
                (nestedFolder.appendingPathComponent("drums.wav"), Data("d".utf8)),
                (nestedFolder.appendingPathComponent("bass.wav"), Data("b".utf8)),
                (nestedFolder.appendingPathComponent("other.wav"), Data("o".utf8))
            ]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let result = await backend.separate(request: request) { _, _ in }

        guard case .success(let folder, let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(folder == nestedFolder)
        #expect(stems.count == 4)
    }

    @Test
    func separate_canceled_returnsCanceledAndDoesNotPublishStems() async {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 0,
            outputLines: ["10%", "20%"],
            errorLines: [],
            filesToWrite: [(outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8))],
            cancellationPoint: 0
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let task = Task {
            await backend.separate(request: request) { _, _ in }
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
        backend.cancel()
        let result = await task.value

        #expect(result == .canceled)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []
        #expect(contents.isEmpty)
    }

    @Test
    func separate_rejectsSecondOperationWhileFirstProcessIsActive() async throws {
        let firstOutput = makeOutputFolder()
        let secondOutput = makeOutputFolder()
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = BlockingConcurrentRunner()
        let backend = makeBackend(settings: settings, runner: runner)
        let firstRequest = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/first.wav"),
            outputFolderURL: firstOutput,
            preset: .fast4
        )
        let secondRequest = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/second.wav"),
            outputFolderURL: secondOutput,
            preset: .fast4
        )

        let firstTask = Task {
            await backend.separate(request: firstRequest) { _, _ in }
        }
        for _ in 0..<100 where runner.invocationCount < 1 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(runner.invocationCount == 1)

        let secondResult = StemSeparationResultCollector()
        let secondTask = Task {
            await secondResult.set(await backend.separate(request: secondRequest) { _, _ in })
        }
        for _ in 0..<100 {
            if await secondResult.value != nil || runner.invocationCount > 1 {
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let capturedSecondResult = await secondResult.value
        #expect(runner.invocationCount == 1)
        #expect(capturedSecondResult == .failed(message: "A stem separation is already running."))

        // Release every call even if a regression started a second process, so the test
        // leaves no intentionally blocked task behind before recording its failure.
        runner.releaseAll()
        _ = await firstTask.value
        _ = await secondTask.value
    }

    @Test
    func separate_missingExecutable_returnsFailed() async {
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: makeOutputFolder(),
            preset: .fast4
        )
        let settings = HelperToolSettings()
        let emptyLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { _ in false }
        )
        let healthChecker = DemucsMLXHealthChecker(locator: emptyLocator)
        let backend = DemucsMLXBackend(
            settings: settings,
            commandBuilder: DemucsMLXCommandBuilder(healthChecker: healthChecker, locator: emptyLocator)
        )

        let result = await backend.separate(request: request) { _, _ in }

        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message == StemSeparationHelperCopy.missingBody)
    }

    @Test
    func separate_nonzeroExit_returnsFailedWithStderr() async {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 1,
            outputLines: ["Loading model"],
            errorLines: ["ModelDownloadError: could not fetch weights"]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let result = await backend.separate(request: request) { _, _ in }

        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("could not fetch weights"))
    }

    @Test
    func separate_unexpectedOutputLayout_returnsFailed() async {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 0,
            outputLines: ["Done"],
            errorLines: [],
            filesToWrite: [(outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8))]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let result = await backend.separate(request: request) { _, _ in }

        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("Missing stems"))
    }

    @Test
    func separate_elapsedTimeInMessages() async {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = FakeStreamingRunner(
            exitCode: 0,
            outputLines: ["50%"],
            errorLines: [],
            filesToWrite: [
                (outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8)),
                (outputFolder.appendingPathComponent("drums.wav"), Data("d".utf8)),
                (outputFolder.appendingPathComponent("bass.wav"), Data("b".utf8)),
                (outputFolder.appendingPathComponent("other.wav"), Data("o".utf8))
            ]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let messageCollector = MessageCollector()
        _ = await backend.separate(request: request) { _, message in
            if let message { messageCollector.add(message) }
        }
        let messages = messageCollector.messages

        #expect(messages.contains { $0.contains("elapsed") })
    }

    @Test
    func separate_chunkWithCarriageReturns_reportsEachUpdateWithoutRegression() async throws {
        let outputFolder = makeOutputFolder()
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: outputFolder,
            preset: .fast4
        )
        let settings = HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/usr/local/bin/demucs-mlx"))
        let runner = ChunkStreamingRunner(
            exitCode: 0,
            chunks: ["Tracks:  10%|█\rTracks:  40%|██\r", "Writing vocals.wav\n"],
            filesToWrite: [
                (outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8)),
                (outputFolder.appendingPathComponent("drums.wav"), Data("d".utf8)),
                (outputFolder.appendingPathComponent("bass.wav"), Data("b".utf8)),
                (outputFolder.appendingPathComponent("other.wav"), Data("o".utf8))
            ]
        )
        let backend = makeBackend(settings: settings, runner: runner)

        let progressCollector = ProgressCollector()
        let result = await backend.separate(request: request) { progress, _ in
            progressCollector.add(progress)
        }
        guard case .success = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        let values = progressCollector.values
        #expect(!values.contains { $0 < 0 })
        #expect(values.contains(0.1))
        #expect(values.contains(0.4))
        // The "Writing" phase carries no percentage; it must repeat the last
        // known fraction instead of jumping back to 0 or -1.
        #expect(values.count >= 3)
        #expect(values.last == 0.4)
        var maxSoFar = 0.0
        for value in values {
            #expect(value >= maxSoFar - 1e-9)
            maxSoFar = max(maxSoFar, value)
        }
    }
}

private func makeBackend(settings: HelperToolSettings, runner: any StreamingExternalProcessRunning) -> DemucsMLXBackend {
    let executables: Set<String> = settings.demucsMlx.map { [$0.path] } ?? []
    let locator = HelperToolLocator(
        managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
        systemDirectories: [],
        isExecutable: { executables.contains($0) }
    )
    let healthChecker = DemucsMLXHealthChecker(locator: locator)
    let commandBuilder = DemucsMLXCommandBuilder(healthChecker: healthChecker, locator: locator)
    return DemucsMLXBackend(
        settings: settings,
        healthChecker: healthChecker,
        commandBuilder: commandBuilder,
        runner: runner
    )
}

private func makeOutputFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
}

private final class MessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var messages: [String] = []
    func add(_ message: String) { lock.withLock { messages.append(message) } }
}

private actor StemSeparationResultCollector {
    private(set) var value: StemSeparationResult?

    func set(_ result: StemSeparationResult) {
        value = result
    }
}

private final class BlockingConcurrentRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: CheckedContinuation<ExternalProcessResult, any Error>] = [:]
    private var invocationTotal = 0
    private var wasReleased = false

    var invocationCount: Int { lock.withLock { invocationTotal } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        lock.withLock { invocationTotal += 1 }
        let invocationID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let releaseImmediately = lock.withLock { () -> Bool in
                guard !wasReleased else { return true }
                continuations[invocationID] = continuation
                return false
            }
            if releaseImmediately {
                continuation.resume(returning: Self.releasedResult)
            }
        }
    }

    func releaseAll() {
        let stored = lock.withLock { () -> [CheckedContinuation<ExternalProcessResult, any Error>] in
            wasReleased = true
            let stored = Array(continuations.values)
            continuations.removeAll()
            return stored
        }
        stored.forEach { $0.resume(returning: Self.releasedResult) }
    }

    private static let releasedResult = ExternalProcessResult(
        exitCode: 1,
        standardOutput: "",
        standardError: "stopped by test"
    )
}

private final class FakeStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {    private let exitCode: Int32
    private let outputLines: [String]
    private let errorLines: [String]
    private let filesToWrite: [(URL, Data)]
    private let cancellationPoint: Int?

    init(
        exitCode: Int32,
        outputLines: [String],
        errorLines: [String],
        filesToWrite: [(URL, Data)] = [],
        cancellationPoint: Int? = nil
    ) {
        self.exitCode = exitCode
        self.outputLines = outputLines
        self.errorLines = errorLines
        self.filesToWrite = filesToWrite
        self.cancellationPoint = cancellationPoint
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        if let cancellationPoint, cancellationPoint == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
        }

        for (index, line) in outputLines.enumerated() {
            try Task.checkCancellation()
            onStandardOutput(line + "\n")
            if let cancellationPoint, cancellationPoint == index + 1 {
                try await Task.sleep(nanoseconds: 50_000_000)
                try Task.checkCancellation()
            }
        }

        for line in errorLines {
            try Task.checkCancellation()
            onStandardError(line + "\n")
        }

        for (url, data) in filesToWrite {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: data)
        }

        var combinedOutput = outputLines.joined(separator: "\n")
        if !combinedOutput.isEmpty { combinedOutput += "\n" }
        var combinedError = errorLines.joined(separator: "\n")
        if !combinedError.isEmpty { combinedError += "\n" }

        return ExternalProcessResult(
            exitCode: exitCode,
            standardOutput: combinedOutput,
            standardError: combinedError
        )
    }
}

private final class ChunkStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    private let exitCode: Int32
    private let chunks: [String]
    private let filesToWrite: [(URL, Data)]

    init(exitCode: Int32, chunks: [String], filesToWrite: [(URL, Data)] = []) {
        self.exitCode = exitCode
        self.chunks = chunks
        self.filesToWrite = filesToWrite
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        for chunk in chunks {
            try Task.checkCancellation()
            onStandardOutput(chunk)
        }
        for (url, data) in filesToWrite {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
        return ExternalProcessResult(
            exitCode: exitCode,
            standardOutput: chunks.joined(),
            standardError: ""
        )
    }
}
