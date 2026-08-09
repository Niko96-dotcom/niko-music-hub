import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct YouTubeStemSeparationWorkflowTests {

    @Test
    func startJob_downloadsAudioThenSeparatesStems() async throws {
        let runner = JobRunner()
        let inbox = FakeOutputInboxStore()
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])

        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: inbox,
            jobRunner: runner
        )
        let downloader = FakeYouTubeAudioDownloader(fileName: "downloaded.wav")
        let workflow = YouTubeStemSeparationWorkflow(
            downloader: downloader,
            stemService: service,
            jobRunner: runner
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = URL(string: "https://www.youtube.com/watch?v=test")!

        let job = workflow.startJob(
            request: YouTubeStemSeparationRequest(sourceURL: sourceURL, outputRootURL: root, preset: .fast4)
        )
        try await waitUntilFinished(runner: runner, job: job)

        #expect(runner.job(id: job.id)?.state == .completed)
        #expect(downloader.requests == [sourceURL])
        #expect(backend.requests.first?.inputURL.lastPathComponent == "downloaded.wav")
        #expect(inbox.items.count == 4)
        #expect(runner.job(id: job.id)?.outputFileURLs.count == 4)
    }

    @Test
    func startJob_rejectsArchiveOutputBeforeCreatingDownloadDirectoryOrLaunchingDownloader() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("youtube-stem-output-guard-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let configuredArchiveAlias = base.appendingPathComponent("configured-archive", isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: configuredArchiveAlias, withDestinationURL: archive)

        let runner = JobRunner()
        let backend = MockStemSeparationBackend()
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: FakeOutputInboxStore(),
            jobRunner: runner,
            archiveRootsProvider: { [configuredArchiveAlias] }
        )
        let downloader = FakeYouTubeAudioDownloader(fileName: "downloaded.wav")
        let workflow = YouTubeStemSeparationWorkflow(
            downloader: downloader,
            stemService: service,
            jobRunner: runner
        )

        let job = workflow.startJob(
            request: YouTubeStemSeparationRequest(
                sourceURL: URL(string: "https://www.youtube.com/watch?v=test")!,
                outputRootURL: archive,
                preset: .fast4
            )
        )
        try await waitUntilFinished(runner: runner, job: job)

        #expect(runner.job(id: job.id)?.state == .failed)
        #expect(downloader.requests.isEmpty)
        #expect(backend.requests.isEmpty)
        #expect(!fileManager.fileExists(atPath: archive.appendingPathComponent("Downloads", isDirectory: true).path))
    }
}

private final class FakeYouTubeAudioDownloader: YouTubeAudioDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private let fileName: String
    private var recordedRequests: [URL] = []

    var requests: [URL] { lock.withLock { recordedRequests } }

    init(fileName: String) {
        self.fileName = fileName
    }

    func downloadAudio(
        from sourceURL: URL,
        to outputDirectory: URL,
        progress: JobProgress
    ) async throws -> URL {
        lock.withLock { recordedRequests.append(sourceURL) }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("audio".utf8))
        progress.update(progress: 1, message: "Downloaded")
        progress.setOutputFileURLs([outputURL])
        return outputURL
    }
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
