@testable import AppCore
@testable import FeatureDownloader
import XCTest

final class DownloaderUseCaseTests: XCTestCase {
    func testYtDlpFailureMessagePrefersStderr() {
        let result = ExternalProcessResult(
            exitCode: 1,
            standardOutput: "title line",
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
        XCTAssertEqual(
            DownloaderUseCase.ytDlpFailureMessage(from: result),
            "ERROR: [youtube] abc: Video unavailable"
        )
    }

    func testYtDlpFailureMessageFallsBackToStdout() {
        let result = ExternalProcessResult(
            exitCode: 1,
            standardOutput: "only stdout",
            standardError: ""
        )
        XCTAssertEqual(DownloaderUseCase.ytDlpFailureMessage(from: result), "only stdout")
    }

    func testSimulateFailureDoesNotEnqueueJob() async {
        let simulateRunner = SimulateFailureRunner()
        let jobRunner = SpyJobRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: YtDlpHealthChecker(
                runner: AvailableVersionRunner(),
                fileExists: { _ in true }
            ),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner
        )

        let url = URL(string: "https://example.com/watch?v=bad")!
        let options = DownloadJobOptions(
            sourceURL: url,
            outputDirectory: URL(fileURLWithPath: "/tmp/out")
        )

        do {
            _ = try await useCase.simulateAndEnqueue(url: url, options: options)
            XCTFail("Expected simulate failure")
        } catch let error as DownloadUseCaseError {
            guard case let .downloadFailed(message) = error else {
                XCTFail("Expected downloadFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Video unavailable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(simulateRunner.runCount, 1)
        XCTAssertEqual(jobRunner.enqueueCount, 0)
    }

    func testSimulateSuccessEnqueuesJob() async throws {
        let simulateRunner = AvailableVersionRunner()
        let jobRunner = SpyJobRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: YtDlpHealthChecker(
                runner: simulateRunner,
                fileExists: { _ in true }
            ),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner
        )

        let url = URL(string: "https://example.com/watch?v=ok")!
        let options = DownloadJobOptions(
            sourceURL: url,
            outputDirectory: URL(fileURLWithPath: "/tmp/out")
        )

        _ = try await useCase.simulateAndEnqueue(url: url, options: options)
        XCTAssertEqual(jobRunner.enqueueCount, 1)
    }

    func testCompletedDownloadLogsDestinationForOutputInbox() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/out/Me at the zoo.webm")
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: SuccessfulDownloader(outputURLs: [outputURL]),
            healthChecker: YtDlpHealthChecker(
                runner: AvailableVersionRunner(),
                fileExists: { _ in true }
            ),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: AvailableVersionRunner()
        )

        let url = URL(string: "https://youtu.be/jNQXAC9IVRw")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(
                sourceURL: url,
                outputDirectory: URL(fileURLWithPath: "/tmp/out")
            )
        )

        let completed = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertTrue(
            completed.logEntries.contains {
                $0.message == "[download] Destination: \(outputURL.path)"
            }
        )
    }

    private func waitForJob(_ id: Job.ID, in runner: JobRunner) async throws -> Job {
        for _ in 0..<50 {
            if let job = runner.job(id: id), job.state == .completed || job.state == .failed {
                return job
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTSkip("Timed out waiting for downloader job to finish")
    }
}

private final class SimulateFailureRunner: ExternalProcessRunning, @unchecked Sendable {
    private(set) var runCount = 0

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        runCount += 1
        XCTAssertTrue(request.arguments.contains("--simulate"))
        return ExternalProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
    }
}

private struct AvailableVersionRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        if request.arguments.contains("--simulate") {
            return ExternalProcessResult(exitCode: 0, standardOutput: "Sample Title", standardError: "")
        }
        return ExternalProcessResult(exitCode: 0, standardOutput: "2026.03.17", standardError: "")
    }
}

private struct NeverCalledDownloadRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        XCTFail("Download runner should not run during simulate-only tests: \(request.arguments)")
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private struct SuccessfulDownloader: DownloadRunning {
    let outputURLs: [URL]

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        progressHandler("[download] 100.0% of 1.0MiB in 00:01")
        return DownloadResult(
            outputURLs: outputURLs,
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

private final class SpyJobRunner: JobRunning, @unchecked Sendable {
    private(set) var enqueueCount = 0

    func listJobs() -> [Job] { [] }
    func job(id: Job.ID) -> Job? { nil }

    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        enqueueCount += 1
        return Job(sourceToolID: sourceToolID, title: title)
    }

    func cancelJob(id: Job.ID) {}
}

private struct FixtureSettingsStore: SettingsStore {
    func loadSettings() throws -> AppSettings {
        AppSettings(
            outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"))
        )
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var settings = try loadSettings()
        update(&settings)
    }
}
