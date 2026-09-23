import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct StemSeparationServiceTests {

    private func makeService(
        backend: MockStemSeparationBackend,
        inbox: FakeOutputInboxStore = FakeOutputInboxStore()
    ) -> (StemSeparationService, JobRunner, FakeOutputInboxStore) {
        let runner = JobRunner()
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: inbox,
            jobRunner: runner
        )
        return (service, runner, inbox)
    }

    @Test
    func startJob_createsOutputFolderUnderConfiguredRoot() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let input = makeInputFile()
        let (service, runner, _) = makeService(backend: backend)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4)

        let job = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: job)

        let outputFolder = backend.requests.first?.outputFolderURL
        #expect(outputFolder?.path.hasPrefix(root.path) == true)
        #expect(outputFolder?.path.contains("Stems") == true)
    }

    @Test
    func startJob_doesNotModifySourceFile() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let input = makeInputFile()
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        let modificationDate = attributes[.modificationDate] as? Date

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let (service, runner, _) = makeService(backend: backend)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4)

        _ = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: runner.listJobs().first!)

        let newAttributes = try FileManager.default.attributesOfItem(atPath: input.path)
        let newModificationDate = newAttributes[.modificationDate] as? Date
        #expect(newModificationDate == modificationDate)
    }

    @Test
    func startJob_addsVerifiedStemsToOutputInbox() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let input = makeInputFile()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inbox = FakeOutputInboxStore()
        let (service, runner, _) = makeService(backend: backend, inbox: inbox)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4)

        let job = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: job)

        #expect(inbox.items.count == 4)
        #expect(Set(inbox.items.map(\.sourceToolID.rawValue)) == ["stem-separation"])
        #expect(inbox.items.allSatisfy { $0.status == .available })
    }

    @Test
    func startJob_prefixesStemFilenamesWithSourceTitle() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let input = makeInputFile()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inbox = FakeOutputInboxStore()
        let (service, runner, _) = makeService(backend: backend, inbox: inbox)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4, title: "Neon Hook")

        let job = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: job)

        let names = Set(inbox.items.map(\.fileURL.lastPathComponent))
        #expect(names == [
            "Neon Hook - Vocals.wav",
            "Neon Hook - Drums.wav",
            "Neon Hook - Bass.wav",
            "Neon Hook - Other.wav"
        ])
        #expect(inbox.items.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    }

    @Test
    func startJob_failedBackend_doesNotAddInboxItems() async throws {
        let backend = MockStemSeparationBackend()
        backend.requestedResult = .failed(message: "mock failure")

        let input = makeInputFile()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inbox = FakeOutputInboxStore()
        let (service, runner, _) = makeService(backend: backend, inbox: inbox)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4)

        let job = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: job)

        #expect(inbox.items.isEmpty)
        #expect(runner.job(id: job.id)?.state == .failed)
    }

    @Test
    func startJob_missingStems_marksJobFailed() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let input = makeInputFile()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inbox = FakeOutputInboxStore()
        let (service, runner, _) = makeService(backend: backend, inbox: inbox)
        let request = StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4)

        let job = service.startJob(request: request)
        try await waitUntilFinished(runner: runner, job: job)

        #expect(runner.job(id: job.id)?.state == .failed)
        #expect(inbox.items.isEmpty)
    }

    @Test
    func startJob_uniqueFoldersForRepeatedRuns() async throws {
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let input = makeInputFile()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let (service, runner, _) = makeService(backend: backend)

        _ = service.startJob(request: StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4))
        _ = service.startJob(request: StemSeparationRequest(inputURL: input, outputRootURL: root, preset: .fast4))

        while runner.listJobs().contains(where: { $0.state == .queued || $0.state == .running }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let folders = backend.requests.map(\.outputFolderURL.path)
        #expect(Set(folders).count == 2)
    }

    @Test
    func startJob_rejectsSymlinkResolvedArchiveRootBeforeCreatingDirectoryOrStartingBackend() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("stem-output-guard-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let configuredArchiveAlias = base.appendingPathComponent("configured-archive", isDirectory: true)
        let input = base.appendingPathComponent("input.wav")
        defer { try? fileManager.removeItem(at: base) }
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: configuredArchiveAlias, withDestinationURL: archive)
        fileManager.createFile(atPath: input.path, contents: Data("input".utf8))

        let backend = MockStemSeparationBackend()
        let runner = JobRunner()
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: FakeOutputInboxStore(),
            jobRunner: runner,
            archiveRootsProvider: { [configuredArchiveAlias] }
        )

        let job = service.startJob(
            request: StemSeparationRequest(inputURL: input, outputRootURL: archive, preset: .fast4)
        )
        try await waitUntilFinished(runner: runner, job: job)

        #expect(runner.job(id: job.id)?.state == .failed)
        #expect(backend.requests.isEmpty)
        #expect(!fileManager.fileExists(atPath: archive.appendingPathComponent("Stems", isDirectory: true).path))
    }

    @Test
    func cancelingJob_terminatesDemucsProcessRunner() async throws {
        let fileManager = FileManager.default
        let outputRoot = fileManager.temporaryDirectory
            .appendingPathComponent("stem-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: outputRoot) }

        let processRunner = BlockingCancellationAwareProcessRunner()
        let executable = URL(fileURLWithPath: "/usr/local/bin/demucs-mlx")
        let locator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { $0 == executable.path }
        )
        let healthChecker = DemucsMLXHealthChecker(locator: locator)
        let backend = DemucsMLXBackend(
            settings: HelperToolSettings(demucsMlx: executable),
            healthChecker: healthChecker,
            commandBuilder: DemucsMLXCommandBuilder(healthChecker: healthChecker, locator: locator),
            runner: processRunner
        )
        let runner = JobRunner()
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: FakeOutputInboxStore(),
            jobRunner: runner
        )

        let job = service.startJob(
            request: StemSeparationRequest(
                inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
                outputRootURL: outputRoot,
                preset: .fast4
            )
        )

        for _ in 0..<100 where !processRunner.didStart {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(processRunner.didStart)

        runner.cancelJob(id: job.id)

        var cancellationReachedProcessRunner = processRunner.cancellationRequested
        for _ in 0..<100 where !cancellationReachedProcessRunner {
            try await Task.sleep(nanoseconds: 10_000_000)
            cancellationReachedProcessRunner = processRunner.cancellationRequested
        }
        if !cancellationReachedProcessRunner {
            // Keep a regression failure from leaving its intentionally blocking fake running.
            backend.cancel()
        }

        #expect(cancellationReachedProcessRunner)
        #expect(runner.job(id: job.id)?.state == .canceled)
        if let outputDirectory = processRunner.outputDirectory {
            let contents = try fileManager.contentsOfDirectory(atPath: outputDirectory.path)
            #expect(contents.isEmpty)
        } else {
            Issue.record("The process runner did not receive the demucs output directory.")
        }
    }
}

private func makeInputFile() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    FileManager.default.createFile(atPath: url.path, contents: Data("input".utf8))
    return url
}

private func waitUntilFinished(runner: JobRunner, job: Job) async throws {
    for _ in 0..<500 {
        guard let current = runner.job(id: job.id) else { return }
        if current.state == .completed || current.state == .failed || current.state == .canceled {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private final class BlockingCancellationAwareProcessRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ExternalProcessResult, any Error>?
    private var started = false
    private var didReceiveCancellation = false
    private var recordedOutputDirectory: URL?

    var didStart: Bool { lock.withLock { started } }
    var cancellationRequested: Bool { lock.withLock { didReceiveCancellation } }
    var outputDirectory: URL? { lock.withLock { recordedOutputDirectory } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        lock.withLock {
            started = true
            if let outputArgumentIndex = request.arguments.firstIndex(of: "--out"),
               request.arguments.indices.contains(outputArgumentIndex + 1) {
                recordedOutputDirectory = URL(
                    fileURLWithPath: request.arguments[outputArgumentIndex + 1],
                    isDirectory: true
                )
            }
        }

        return try await withTaskCancellationHandler(operation: {
            try await self.waitForTermination()
        }, onCancel: {
            self.terminateProcess()
        })
    }

    private func waitForTermination() async throws -> ExternalProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let cancelImmediately = lock.withLock { () -> Bool in
                if didReceiveCancellation {
                    return true
                }
                self.continuation = continuation
                return false
            }
            if cancelImmediately {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func terminateProcess() {
        let continuation = lock.withLock { () -> CheckedContinuation<ExternalProcessResult, any Error>? in
            didReceiveCancellation = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

final class FakeOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OutputInboxItem] = []

    var items: [OutputInboxItem] { lock.withLock { stored } }

    func listItems() throws -> [OutputInboxItem] { lock.withLock { stored } }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock { stored.append(item) }
    }

    func updateItem(_ item: OutputInboxItem) throws {
        lock.withLock {
            if let index = stored.firstIndex(where: { $0.id == item.id }) {
                stored[index] = item
            }
        }
    }

    func refreshAvailability() throws {
        lock.withLock {
            stored = stored.map { item in
                var copy = item
                if FileManager.default.fileExists(atPath: item.fileURL.path) {
                    copy.status = .available
                } else {
                    copy.status = .missing
                }
                return copy
            }
        }
    }
}
