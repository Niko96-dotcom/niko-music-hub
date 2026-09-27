@testable import AppCore
@testable import FeatureDownloader
import XCTest

final class DownloaderUseCaseTests: XCTestCase {
    private func ytDlpLocator() -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { $0 == "/opt/homebrew/bin/yt-dlp" }
        )
    }

    private func healthChecker(runner: any ExternalProcessRunning) -> YtDlpHealthChecker {
        YtDlpHealthChecker(runner: runner, referenceDate: YtDlpVersionPolicy.parseVersionDate("2026.09.27"), locator: ytDlpLocator())
    }

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
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner,
            locator: ytDlpLocator()
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
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertFalse(failure.isRetryable)
            XCTAssertTrue(failure.message.contains("Video unavailable"))
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
            healthChecker: healthChecker(runner: simulateRunner),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner,
            locator: ytDlpLocator()
        )

        let url = URL(string: "https://example.com/watch?v=ok")!
        let options = DownloadJobOptions(
            sourceURL: url,
            outputDirectory: URL(fileURLWithPath: "/tmp/out")
        )

        _ = try await useCase.simulateAndEnqueue(url: url, options: options)
        XCTAssertEqual(jobRunner.enqueueCount, 1)
    }

    func testCompletedDownloadSetsStructuredOutputURLs() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/out/Me at the zoo.webm")
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: SuccessfulDownloader(outputs: [
                VerifiedDownloadOutput(url: outputURL, isAlreadyExisting: false),
            ]),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
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
        XCTAssertEqual(completed.outputFileURLs, [outputURL])
    }

    func testSimulateSuccessUsesTitleForJobName() async throws {
        let simulateRunner = TitleSimulateRunner(title: "Me at the zoo")
        let jobRunner = SpyJobRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner,
            locator: ytDlpLocator()
        )

        let url = URL(string: "https://youtu.be/jNQXAC9IVRw")!
        _ = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(
                sourceURL: url,
                outputDirectory: URL(fileURLWithPath: "/tmp/out")
            )
        )

        XCTAssertEqual(jobRunner.lastTitle, "Download: Me at the zoo")
    }

    func testInternalTimeoutWordingNeverRetries() async throws {
        let downloader = InternalTimeoutMessageDownloader()
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://www.youtube.com/watch?v=internal")!

        do {
            _ = try await useCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                    retries: 3
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected failure")
        } catch let error as DownloadUseCaseError {
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertTrue(failure.message.contains("timeout"))
            XCTAssertFalse(failure.isRetryable)
        }
        XCTAssertEqual(downloader.attemptCount, 1)
    }

    func testPermanentStderrWithStdoutTimeoutPathPerformsSingleAttempt() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usecase-permanent-timeout-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let downloadRunner = CountingPermanentStderrTimeoutPathRunner()
        let downloader = YtDlpDownloader(runner: downloadRunner)
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(outputRoot: outputDir),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=permanent")!

        do {
            _ = try await useCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: outputDir,
                    retries: 3
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected permanent failure")
        } catch let error as DownloadUseCaseError {
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertFalse(failure.isRetryable)
            XCTAssertTrue(failure.message.contains("Video unavailable"))
        }
        XCTAssertEqual(downloadRunner.runCount, 1)
    }

    func testNonZeroExitKeepsVerifiedOutputsOnFailedJob() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usecase-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let freshURL = outputDir.appendingPathComponent("fresh-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: freshURL.path, contents: Data("x".utf8))
        let existingURL = outputDir.appendingPathComponent("existing-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data("x".utf8))
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: PartialFailureDownloader(urls: [
                VerifiedDownloadOutput(url: freshURL, isAlreadyExisting: false),
                VerifiedDownloadOutput(url: existingURL, isAlreadyExisting: true),
            ]),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(outputRoot: outputDir),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
        )

        let url = URL(string: "https://example.com/playlist?list=abc")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: outputDir, retries: 1)
        )

        let finished = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(finished.state, .failed)
        XCTAssertNil(finished.failureReason)
        XCTAssertEqual(Set(finished.outputFileURLs), Set([freshURL, existingURL]))
        XCTAssertTrue(finished.message.contains("403"))
    }

    func testPureSkipFailsWithAlreadyExistsReasonAndKeepsOutputs() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usecase-skip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let existingURL = outputDir.appendingPathComponent("existing-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data("x".utf8))
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: SuccessfulDownloader(outputs: [
                VerifiedDownloadOutput(url: existingURL, isAlreadyExisting: true),
            ]),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(outputRoot: outputDir),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
        )

        let url = URL(string: "https://example.com/watch?v=skip")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: outputDir, retries: 1)
        )

        let finished = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(finished.state, .failed)
        XCTAssertEqual(finished.failureReason, .downloadAlreadyExists)
        XCTAssertEqual(finished.outputFileURLs, [existingURL])
    }

    func testMissingYtDlpFailsWithDownloaderHelperReason() async throws {
        let missingLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { _ in false }
        )
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: YtDlpHealthChecker(runner: AvailableVersionRunner(), locator: missingLocator),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(settings: AppSettings(
                outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
                helperTools: HelperToolSettings(ytDlp: nil)
            )),
            simulateRunner: CapturingSimulateRunner(),
            locator: missingLocator
        )
        let url = URL(string: "https://example.com/watch?v=ok")!
        do {
            _ = try await useCase.simulateAndEnqueue(
                url: url,
                options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"))
            )
            XCTFail("Expected missing helper error")
        } catch let error as DownloadUseCaseError {
            XCTAssertEqual(error.jobFailureReason, .downloaderHelperUnavailable)
            XCTAssertNotEqual(error.jobFailureReason, .helperUnavailable)
        }
    }

    func testStallFailureDoesNotRetry() async throws {
        let downloader = StallThrowingDownloader()
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=stall")!

        do {
            _ = try await useCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                    retries: 3
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected stall failure")
        } catch let error as DownloadUseCaseError {
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertEqual(failure.kind, .downloadStalled)
            XCTAssertFalse(failure.isRetryable)
        }
        XCTAssertEqual(downloader.attemptCount, 1)
    }

    func testHTTP403RetriesWithAFreshDownloadAttempt() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/out/recovered.wav")
        let downloader = FirstAttempt403Downloader(outputURL: outputURL)
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://www.youtube.com/watch?v=retry")!

        let outputs = try await useCase.download(
            url: sourceURL,
            options: DownloadJobOptions(
                sourceURL: sourceURL,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                retries: 2
            ),
            progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
        )

        XCTAssertEqual(outputs, [outputURL])
        XCTAssertEqual(downloader.attemptCount, 2)
    }

    func testSimulateUsesFormatSelectionAndNoPlaylist() async throws {
        let simulateRunner = CapturingSimulateRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            simulateRunner: simulateRunner,
            locator: ytDlpLocator()
        )

        let url = URL(string: "https://example.com/watch?v=ok")!
        _ = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(
                sourceURL: url,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                formatSelection: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .wav)
            )
        )

        let wavArgs = try XCTUnwrap(simulateRunner.lastRequest?.arguments)
        XCTAssertTrue(wavArgs.contains("--simulate"))
        XCTAssertTrue(wavArgs.contains("--no-playlist"))
        XCTAssertTrue(wavArgs.contains("--extract-audio"))
        XCTAssertTrue(wavArgs.contains("wav"))
        XCTAssertTrue(wavArgs.contains("--force-ipv4"))
        XCTAssertEqual(simulateRunner.lastRequest?.timeoutSeconds, 30)

        simulateRunner.reset()
        _ = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(
                sourceURL: url,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                formatSelection: DownloadFormatSelection(mediaKind: .videoWithAudio, videoQuality: .mp4_720)
            )
        )
        let videoArgs = try XCTUnwrap(simulateRunner.lastRequest?.arguments)
        XCTAssertTrue(videoArgs.contains { $0.contains("height<=720") })
        XCTAssertTrue(videoArgs.contains("--no-playlist"))
    }

    func testParseProgressFromNIKOProgressMarker() {
        XCTAssertEqual(DownloaderUseCase.parseProgress(from: "NIKO_PROGRESS: 50.0%"), 0.5)
    }

    func testPlaylistModeOmitsNoPlaylistFlag() {
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com/playlist?list=abc")!,
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            playlistMode: .playlist
        )
        let args = YtDlpDownloadCommandBuilder.downloadArguments(
            for: request,
            partialDirectory: request.outputDirectory.appendingPathComponent(".nmh-partial-test", isDirectory: true)
        )
        XCTAssertFalse(args.contains("--no-playlist"))
        XCTAssertTrue(args.contains("--max-downloads"))
    }

    func testAudioPostProcessingRequestCarriesConfiguredFFmpegLocationAndHelperPath() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/out/Sample.wav")
        let downloader = CapturingDownloader(outputs: [
            VerifiedDownloadOutput(url: outputURL, isAlreadyExisting: false),
        ])
        let jobRunner = JobRunner()
        let helperDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloader-helper-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: helperDirectory) }
        _ = FileManager.default.createFile(atPath: helperDirectory.appendingPathComponent("ffmpeg").path, contents: Data())
        _ = FileManager.default.createFile(atPath: helperDirectory.appendingPathComponent("ffprobe").path, contents: Data())
        _ = FileManager.default.createFile(atPath: helperDirectory.appendingPathComponent("yt-dlp").path, contents: Data())
        let ffmpegURL = helperDirectory.appendingPathComponent("ffmpeg")
        let ffprobeURL = helperDirectory.appendingPathComponent("ffprobe")
        let ytDlpURL = helperDirectory.appendingPathComponent("yt-dlp")
        let settings = AppSettings(
            outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
            helperTools: HelperToolSettings(
                ffmpeg: ffmpegURL,
                ffprobe: ffprobeURL,
                ytDlp: ytDlpURL
            )
        )
        let fixtureLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { [ffmpegURL.path, ffprobeURL.path, ytDlpURL.path].contains($0) }
        )
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: YtDlpHealthChecker(
                runner: AvailableVersionRunner(),
                locator: fixtureLocator
            ),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(settings: settings),
            simulateRunner: AvailableVersionRunner(),
            locator: fixtureLocator
        )

        let url = URL(string: "https://example.com/audio")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(
                sourceURL: url,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                formatSelection: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .wav)
            )
        )

        let completed = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(completed.state, .completed)
        let request = try XCTUnwrap(downloader.requests.first)
        XCTAssertEqual(request.ffmpegLocationURL, helperDirectory)
        XCTAssertTrue(request.helperSearchDirectories.contains(helperDirectory))
    }

    func testSavedDeletedYtDlpPathFallsBackToFixture() async throws {
        let fixtureURL = URL(fileURLWithPath: "/fixture/bin/yt-dlp")
        let fixtureLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { $0 == fixtureURL.path }
        )
        let settings = AppSettings(
            outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/deleted/yt-dlp"))
        )
        let checker = YtDlpHealthChecker(
            runner: AvailableVersionRunner(),
            // Close to the fake's 2026.08.19 so the freshness policy passes.
            referenceDate: Date(timeIntervalSince1970: 1_790_000_000),
            locator: fixtureLocator
        )
        let availability = await checker.availability(settings: settings.helperTools)
        guard case .available = availability else {
            return XCTFail("Expected available via fallback, got \(availability)")
        }
        XCTAssertEqual(checker.resolvedYtDlpURL(settings: settings.helperTools), fixtureURL)

        let simulateRunner = CapturingSimulateRunner()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: checker,
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(settings: settings),
            simulateRunner: simulateRunner,
            locator: fixtureLocator
        )
        let url = URL(string: "https://example.com/watch?v=ok")!
        _ = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"))
        )
        XCTAssertEqual(simulateRunner.lastRequest?.executableURL, fixtureURL)
    }

    func testMissingYtDlpUsesInstallToolsCopy() async {
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: YtDlpHealthChecker(
                runner: AvailableVersionRunner(),
                locator: HelperToolLocator(
                    managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                    systemDirectories: [],
                    isExecutable: { _ in false }
                )
            ),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(settings: AppSettings(
                outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
                helperTools: HelperToolSettings(ytDlp: nil)
            )),
            simulateRunner: CapturingSimulateRunner(),
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { _ in false }
            )
        )
        let url = URL(string: "https://example.com/watch?v=ok")!
        do {
            _ = try await useCase.simulateAndEnqueue(
                url: url,
                options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"))
            )
            XCTFail("Expected missing error")
        } catch let error as DownloadUseCaseError {
            XCTAssertEqual(error, .ytDlpUnavailable(DownloaderCopy.ytDlpMissing))
            XCTAssertEqual(DownloaderCopy.ytDlpMissing, "yt-dlp is not installed. Use Install Tools to add it.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOutdatedCopyUsesInstallTools() {
        XCTAssertEqual(
            DownloaderCopy.outdatedYtDlp(current: "2023.01.01", minimumExpected: "2024.01.01"),
            "yt-dlp 2023.01.01 is outdated (expected 2024.01.01 or newer). Use Install Tools to update it."
        )
    }

    func testDirectDownloadWithAllExistingReturnsURLsInsteadOfThrowing() async throws {
        let existingURL = URL(fileURLWithPath: "/tmp/out/existing-\(UUID().uuidString).mp4")
        let useCase = DownloaderUseCase(
            downloader: SuccessfulDownloader(outputs: [
                VerifiedDownloadOutput(url: existingURL, isAlreadyExisting: true),
            ]),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=skip")!
        let outputs = try await useCase.download(
            url: sourceURL,
            options: DownloadJobOptions(
                sourceURL: sourceURL,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                retries: 1
            ),
            progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
        )
        XCTAssertEqual(outputs, [existingURL])
    }

    func testRetryAccumulatesFreshOutputAcrossFailedAttempts() async throws {
        let freshURL = URL(fileURLWithPath: "/tmp/out/fresh-\(UUID().uuidString).mp4")
        let downloader = FreshThenEmptyFailureDownloader(freshURL: freshURL)
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/playlist?list=abc")!
        do {
            _ = try await useCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                    retries: 2
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected accumulated failure")
        } catch let error as DownloadUseCaseError {
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertFalse(failure.isRetryable)
            XCTAssertEqual(failure.outputs.map(\.url), [freshURL])
        }
        XCTAssertEqual(downloader.attemptCount, 2)
    }

    func testRetrySkipOfSameFileStaysFreshForDirectDownload() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/out/same-\(UUID().uuidString).mp4")
        let downloader = FreshFailureThenSkipSuccessDownloader(fileURL: fileURL)
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=same")!
        let outputs = try await useCase.download(
            url: sourceURL,
            options: DownloadJobOptions(
                sourceURL: sourceURL,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                retries: 2
            ),
            progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
        )
        XCTAssertEqual(outputs, [fileURL])
        XCTAssertEqual(downloader.attemptCount, 2)
    }

    func testRetrySkipOfSameFileCompletesJobInsteadOfAlreadyExists() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/out/same-job-\(UUID().uuidString).mp4")
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: FreshFailureThenSkipSuccessDownloader(fileURL: fileURL),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
        )
        let url = URL(string: "https://example.com/watch?v=same")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"), retries: 2)
        )
        let finished = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(finished.state, .completed)
        XCTAssertNil(finished.failureReason)
        XCTAssertEqual(finished.outputFileURLs, [fileURL])
    }

    func testRetryEmptyFinalSuccessFailsWhilePreservingAccumulatedOutput() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/out/empty-final-\(UUID().uuidString).mp4")
        let downloader = FreshFailureThenEmptySuccessDownloader(fileURL: fileURL)
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
        )
        let url = URL(string: "https://example.com/watch?v=empty-final")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"), retries: 2)
        )
        let finished = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(finished.state, .failed)
        XCTAssertNil(finished.failureReason)
        XCTAssertEqual(finished.outputFileURLs, [fileURL])
        XCTAssertEqual(finished.message, "The retry finished without new files. Files from the earlier attempt were kept.")
        XCTAssertEqual(downloader.attemptCount, 2)
    }

    func testSingleEmptySuccessFailsWithOutputNotFound() async throws {
        let useCase = DownloaderUseCase(
            downloader: SuccessfulDownloader(outputs: []),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=empty")!

        do {
            _ = try await useCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                    retries: 2
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected outputNotFound")
        } catch let error as DownloadUseCaseError {
            XCTAssertEqual(error, .outputNotFound)
            XCTAssertEqual(error.localizedDescription, "No output files found after download.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetrySuccessReturnsOnlyFinalAttemptOutputs() async throws {
        let m4aURL = URL(fileURLWithPath: "/tmp/out/retry-\(UUID().uuidString).m4a")
        let wavURL = URL(fileURLWithPath: "/tmp/out/retry-\(UUID().uuidString).wav")
        let useCase = DownloaderUseCase(
            downloader: FreshM4aThenFreshWavDownloader(m4aURL: m4aURL, wavURL: wavURL),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=retry-format")!

        let outputs = try await useCase.download(
            url: sourceURL,
            options: DownloadJobOptions(
                sourceURL: sourceURL,
                outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                retries: 2
            ),
            progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
        )
        XCTAssertEqual(outputs, [wavURL])
    }

    func testRetrySuccessKeepsAllAttemptsOnJobWhileReturningFinalAttempt() async throws {
        let m4aURL = URL(fileURLWithPath: "/tmp/out/retry-job-\(UUID().uuidString).m4a")
        let wavURL = URL(fileURLWithPath: "/tmp/out/retry-job-\(UUID().uuidString).wav")
        let jobRunner = JobRunner()
        let useCase = DownloaderUseCase(
            downloader: FreshM4aThenFreshWavDownloader(m4aURL: m4aURL, wavURL: wavURL),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: jobRunner,
            settingsStore: FixtureSettingsStore(),
            simulateRunner: AvailableVersionRunner(),
            locator: ytDlpLocator()
        )
        let url = URL(string: "https://example.com/watch?v=retry-format")!
        let job = try await useCase.simulateAndEnqueue(
            url: url,
            options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"), retries: 2)
        )
        let finished = try await waitForJob(job.id, in: jobRunner)
        XCTAssertEqual(finished.state, .completed)
        XCTAssertNil(finished.failureReason)
        XCTAssertEqual(Set(finished.outputFileURLs), Set([m4aURL, wavURL]))
    }

    func testNonzeroExitWithoutFailureIsFailClosed() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/out/final-\(UUID().uuidString).mp4")
        let outputs = [VerifiedDownloadOutput(url: outputURL, isAlreadyExisting: false)]
        // Representation is fail-closed: init synthesizes a non-retryable failure.
        let inconsistent = DownloadResult(
            outputs: outputs,
            sourceURL: URL(string: "https://example.com")!,
            exitCode: 1,
            standardError: "boom",
            failure: nil
        )
        XCTAssertNotNil(inconsistent.failure)
        XCTAssertEqual(inconsistent.failure?.isRetryable, false)
        // Direct path through a conformer returning nonzero exit without failure
        // must never be treated as success.
        let conformer = NonzeroNilFailureDownloader(outputs: outputs)
        let failingUseCase = DownloaderUseCase(
            downloader: conformer,
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            locator: ytDlpLocator()
        )
        let sourceURL = URL(string: "https://example.com/watch?v=bad")!
        do {
            _ = try await failingUseCase.download(
                url: sourceURL,
                options: DownloadJobOptions(
                    sourceURL: sourceURL,
                    outputDirectory: URL(fileURLWithPath: "/tmp/out"),
                    retries: 1
                ),
                progress: JobProgress(updateHandler: { _, _ in }, logHandler: { _ in })
            )
            XCTFail("Expected fail-closed failure")
        } catch let error as DownloadUseCaseError {
            guard case let .failed(failure) = error else {
                XCTFail("Expected typed failure, got \(error)")
                return
            }
            XCTAssertFalse(failure.isRetryable)
            XCTAssertEqual(failure.outputs.map(\.url), [outputURL])
        }
    }

    func testSimulateCancellationPropagates() async {
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(runner: NeverCalledDownloadRunner()),
            healthChecker: healthChecker(runner: AvailableVersionRunner()),
            jobRunner: SpyJobRunner(),
            settingsStore: FixtureSettingsStore(),
            simulateRunner: CancellingSimulateRunner(),
            locator: ytDlpLocator()
        )
        let url = URL(string: "https://example.com/watch?v=ok")!
        do {
            _ = try await useCase.simulateAndEnqueue(
                url: url,
                options: DownloadJobOptions(sourceURL: url, outputDirectory: URL(fileURLWithPath: "/tmp/out"))
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation preserved through simulation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func waitForJob(_ id: Job.ID, in runner: JobRunner) async throws -> Job {
        // Bounded wait covering real retry backoff (2s for the first retry).
        // Uses the terminal Job updates stream with a bounded timeout.
        do {
            return try await withThrowingTaskGroup(of: Job.self) { group in
                group.addTask {
                    for await job in runner.updates(for: id) {
                        if job.state == .completed || job.state == .failed {
                            return job
                        }
                    }
                    throw DownloaderUseCaseTestError.timeout
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw DownloaderUseCaseTestError.timeout
                }
                guard let result = try await group.next() else {
                    throw DownloaderUseCaseTestError.timeout
                }
                group.cancelAll()
                return result
            }
        } catch {
            XCTFail("Timed out waiting for downloader job to finish")
            throw error
        }
    }
}

private enum DownloaderUseCaseTestError: Error {
    case timeout
}

private final class CapturingSimulateRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?

    var lastRequest: ExternalProcessRequest? {
        lock.withLock { request }
    }

    func reset() {
        lock.withLock { request = nil }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { self.request = request }
        return ExternalProcessResult(exitCode: 0, standardOutput: "Sample Title", standardError: "")
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
        return ExternalProcessResult(exitCode: 0, standardOutput: "2026.08.19", standardError: "")
    }
}

private struct NeverCalledDownloadRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        XCTFail("Download runner should not run during simulate-only tests: \(request.arguments)")
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private final class CountingPermanentStderrTimeoutPathRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRunCount = 0

    var runCount: Int {
        lock.withLock { storedRunCount }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { storedRunCount += 1 }
        return ExternalProcessResult(
            exitCode: 1,
            standardOutput: "[download] Destination: /fixture/Timeout [id].mp4\n",
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
    }
}

private struct SuccessfulDownloader: DownloadRunning {
    let outputs: [VerifiedDownloadOutput]

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        progressHandler("[download] 100.0% of 1.0MiB in 00:01")
        return DownloadResult(
            outputs: outputs,
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

private final class CapturingDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let outputs: [VerifiedDownloadOutput]
    private var storedRequests: [DownloadRequest] = []

    var requests: [DownloadRequest] {
        lock.withLock { storedRequests }
    }

    init(outputs: [VerifiedDownloadOutput]) {
        self.outputs = outputs
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        lock.withLock {
            storedRequests.append(request)
        }
        progressHandler("[download] 100.0% of 1.0MiB in 00:01")
        return DownloadResult(
            outputs: outputs,
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

/// Typed external 403 on attempt 1 (retryable), success on attempt 2.
private final class FirstAttempt403Downloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        let attempt = lock.withLock { () -> Int in
            storedAttemptCount += 1
            return storedAttemptCount
        }
        if attempt == 1 {
            let outputs: [VerifiedDownloadOutput] = []
            return DownloadResult(
                outputs: outputs,
                sourceURL: request.sourceURL,
                exitCode: 1,
                standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                    isRetryable: true,
                    outputs: outputs
                )
            )
        }
        return DownloadResult(
            outputs: [VerifiedDownloadOutput(url: outputURL, isAlreadyExisting: false)],
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

/// Internal failure whose presentation text mentions a timeout: must never
/// retry because retryability is typed, not parsed.
private final class InternalTimeoutMessageDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        lock.withLock { storedAttemptCount += 1 }
        throw DownloadUseCaseError.failed(DownloadFailure(
            kind: .processFailed,
            message: "internal scheduler timeout before dispatch",
            isRetryable: false,
            outputs: []
        ))
    }
}

private struct PartialFailureDownloader: DownloadRunning {
    let urls: [VerifiedDownloadOutput]

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        DownloadResult(
            outputs: urls,
            sourceURL: request.sourceURL,
            exitCode: 1,
            standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
            failure: DownloadFailure(
                kind: .processFailed,
                message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                isRetryable: false,
                outputs: urls
            )
        )
    }
}

private final class StallThrowingDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        lock.withLock { storedAttemptCount += 1 }
        throw DownloadError.failed(DownloadFailure(
            kind: .downloadStalled,
            message: DownloadStallMonitor.stallErrorMessage,
            isRetryable: false,
            outputs: []
        ))
    }
}

private struct TitleSimulateRunner: ExternalProcessRunning {
    let title: String

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        if request.arguments.contains("--simulate") {
            return ExternalProcessResult(exitCode: 0, standardOutput: title, standardError: "")
        }
        return ExternalProcessResult(exitCode: 0, standardOutput: "2026.08.19", standardError: "")
    }
}

private struct CancellingSimulateRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        throw CancellationError()
    }
}

/// Attempt 1: verified fresh output plus retryable failure; attempt 2: empty
/// non-retryable failure. Final failure must retain the fresh output.
private final class FreshThenEmptyFailureDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let freshURL: URL
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    init(freshURL: URL) {
        self.freshURL = freshURL
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        let attempt = lock.withLock { () -> Int in
            storedAttemptCount += 1
            return storedAttemptCount
        }
        if attempt == 1 {
            let outputs = [VerifiedDownloadOutput(url: freshURL, isAlreadyExisting: false)]
            return DownloadResult(
                outputs: outputs,
                sourceURL: request.sourceURL,
                exitCode: 1,
                standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                    isRetryable: true,
                    outputs: outputs
                )
            )
        }
        return DownloadResult(
            outputs: [],
            sourceURL: request.sourceURL,
            exitCode: 1,
            standardError: "ERROR: [youtube] abc: Video unavailable",
            failure: DownloadFailure(
                kind: .processFailed,
                message: "ERROR: [youtube] abc: Video unavailable",
                isRetryable: false,
                outputs: []
            )
        )
    }
}

/// Retry 1 fails retryably with a fresh file; retry 2 reports the same file
/// as a skip success. Fresh provenance must win (Downloaded, not all-existing).
private final class FreshFailureThenSkipSuccessDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        let attempt = lock.withLock { () -> Int in
            storedAttemptCount += 1
            return storedAttemptCount
        }
        if attempt == 1 {
            let outputs = [VerifiedDownloadOutput(url: fileURL, isAlreadyExisting: false)]
            return DownloadResult(
                outputs: outputs,
                sourceURL: request.sourceURL,
                exitCode: 1,
                standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                    isRetryable: true,
                    outputs: outputs
                )
            )
        }
        return DownloadResult(
            outputs: [VerifiedDownloadOutput(url: fileURL, isAlreadyExisting: true)],
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

/// Attempt 1: verified fresh output plus retryable failure; attempt 2:
/// exit-0 success with zero outputs. The empty final success must fail
/// while the failed Job keeps the accumulated output.
private final class FreshFailureThenEmptySuccessDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        let attempt = lock.withLock { () -> Int in
            storedAttemptCount += 1
            return storedAttemptCount
        }
        if attempt == 1 {
            let outputs = [VerifiedDownloadOutput(url: fileURL, isAlreadyExisting: false)]
            return DownloadResult(
                outputs: outputs,
                sourceURL: request.sourceURL,
                exitCode: 1,
                standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                    isRetryable: true,
                    outputs: outputs
                )
            )
        }
        return DownloadResult(
            outputs: [],
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

/// Attempt 1: retryable failure with a fresh m4a; attempt 2: exit-0 success
/// with only a fresh wav. Success must return only the final attempt while
/// the Job keeps both files.
private final class FreshM4aThenFreshWavDownloader: DownloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let m4aURL: URL
    private let wavURL: URL
    private var storedAttemptCount = 0

    var attemptCount: Int {
        lock.withLock { storedAttemptCount }
    }

    init(m4aURL: URL, wavURL: URL) {
        self.m4aURL = m4aURL
        self.wavURL = wavURL
    }

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        let attempt = lock.withLock { () -> Int in
            storedAttemptCount += 1
            return storedAttemptCount
        }
        if attempt == 1 {
            let outputs = [VerifiedDownloadOutput(url: m4aURL, isAlreadyExisting: false)]
            return DownloadResult(
                outputs: outputs,
                sourceURL: request.sourceURL,
                exitCode: 1,
                standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                    isRetryable: true,
                    outputs: outputs
                )
            )
        }
        return DownloadResult(
            outputs: [VerifiedDownloadOutput(url: wavURL, isAlreadyExisting: false)],
            sourceURL: request.sourceURL,
            exitCode: 0,
            standardError: ""
        )
    }
}

/// Fail-closed conformer: nonzero exit with nil failure must never succeed.
private struct NonzeroNilFailureDownloader: DownloadRunning {
    let outputs: [VerifiedDownloadOutput]

    func download(
        _ request: DownloadRequest,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadResult {
        var result = DownloadResult(
            outputs: outputs,
            sourceURL: request.sourceURL,
            exitCode: 1,
            standardError: "boom",
            failure: nil
        )
        result.failure = nil // Exercise a mutable conformer bypassing initializer normalization.
        return result
    }
}

private final class SpyJobRunner: JobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var enqueueCount = 0
    private(set) var lastTitle: String?

    func listJobs() -> [Job] { [] }
    func job(id: Job.ID) -> Job? { nil }

    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        lock.withLock {
            enqueueCount += 1
            lastTitle = title
        }
        return Job(sourceToolID: sourceToolID, title: title)
    }

    func cancelJob(id: Job.ID) {}
}

private struct FixtureSettingsStore: SettingsStore {
    var settings: AppSettings

    init(settings: AppSettings = AppSettings(
        outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/out")),
        helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"))
    )) {
        self.settings = settings
    }

    init(outputRoot: URL) {
        self.settings = AppSettings(
            outputFolder: StoredFolderLocation(url: outputRoot),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"))
        )
    }

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var settings = try loadSettings()
        update(&settings)
    }
}
