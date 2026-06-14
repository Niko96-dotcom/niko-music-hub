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
            errorLines: [],
            filesToWrite: [
                (outputFolder.appendingPathComponent("vocals.wav"), Data("v".utf8)),
                (outputFolder.appendingPathComponent("drums.wav"), Data("d".utf8)),
                (outputFolder.appendingPathComponent("bass.wav"), Data("b".utf8)),
                (outputFolder.appendingPathComponent("other.wav"), Data("o".utf8))
            ]
        )
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

        let progressCollector = ProgressCollector()
        let result = await backend.separate(request: request) { progress, _ in
            if progress >= 0 {
                progressCollector.add(progress)
            }
        }
        let progressValues = progressCollector.values

        guard case .success(let folder, let stems) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(folder == outputFolder)
        #expect(stems.count == 4)
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
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

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
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

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
    func separate_missingExecutable_returnsFailed() async {
        let request = StemSeparationBackendRequest(
            inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
            outputFolderURL: makeOutputFolder(),
            preset: .fast4
        )
        let settings = HelperToolSettings()
        let healthChecker = DemucsMLXHealthChecker(fileExists: { _ in false })
        let backend = DemucsMLXBackend(
            settings: settings,
            commandBuilder: DemucsMLXCommandBuilder(healthChecker: healthChecker)
        )

        let result = await backend.separate(request: request) { _, _ in }

        guard case .failed(let message) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect(message.contains("executable") || message.contains("command"))
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
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

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
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

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
        let backend = DemucsMLXBackend(settings: settings, runner: runner)

        let messageCollector = MessageCollector()
        _ = await backend.separate(request: request) { _, message in
            if let message { messageCollector.add(message) }
        }
        let messages = messageCollector.messages

        #expect(messages.contains { $0.contains("elapsed") })
    }
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

private final class FakeStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    private let exitCode: Int32
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
