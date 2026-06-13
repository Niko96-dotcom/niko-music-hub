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
