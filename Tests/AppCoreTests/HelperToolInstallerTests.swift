import AppCore
import CryptoKit
import Foundation
import XCTest

final class HelperToolInstallerTests: XCTestCase {
    func testURLSessionRequestErrorsBecomeDownloadFailed() async throws {
        // An unsupported scheme fails inside URLSession without any network access.
        let url = try XCTUnwrap(URL(string: "nmh-unsupported://example.invalid/tool.sha256"))
        let downloader = URLSessionHelperDownloader()
        do {
            _ = try await downloader.fetchText(url)
            XCTFail("fetchText should throw")
        } catch let error as HelperInstallError {
            guard case .downloadFailed = error else { return XCTFail("unexpected error \(error)") }
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("tool")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        do {
            _ = try await downloader.download(url, to: destination, progress: { _ in })
            XCTFail("download should throw")
        } catch let error as HelperInstallError {
            guard case .downloadFailed = error else { return XCTFail("unexpected error \(error)") }
        }
    }

    @MainActor
    func testDirectoriesAndDirectorySymlinksAreNotInstalledOrReady() throws {
        for symbolicLink in [false, true] {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let locator = HelperToolLocator(
                managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
                systemDirectories: []
            )
            for tool in HelperTool.allCases {
                let candidate = locator.managedExecutableURL(for: tool)
                let directory = symbolicLink ? candidate.appendingPathExtension("directory") : candidate
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
                if symbolicLink {
                    try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: directory)
                }
            }
            let installer = HelperToolInstaller(
                locator: locator,
                downloader: FakeDownloader(),
                processRunner: FakeRunner()
            )
            let model = HelperToolSetupModel(
                locator: locator,
                installer: installer,
                settingsProvider: { HelperToolSettings() }
            )

            model.refresh()
            for bundle in HelperToolBundle.allCases {
                XCTAssertFalse(installer.isInstalled(bundle))
                XCTAssertEqual(model.states[bundle], .notInstalled)
            }
            XCTAssertFalse(model.allInstalled)
        }
    }

    @MainActor
    func testExecutableFilesAndSymlinksAreInstalledAndReady() throws {
        for symbolicLink in [false, true] {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let locator = HelperToolLocator(
                managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
                systemDirectories: []
            )
            try FileManager.default.createDirectory(
                at: locator.managedBinDirectory,
                withIntermediateDirectories: true
            )
            for tool in HelperTool.allCases {
                let candidate = locator.managedExecutableURL(for: tool)
                let executable = symbolicLink ? candidate.appendingPathExtension("executable") : candidate
                try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
                if symbolicLink {
                    try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: executable)
                }
            }
            let installer = HelperToolInstaller(
                locator: locator,
                downloader: FakeDownloader(),
                processRunner: FakeRunner()
            )
            let model = HelperToolSetupModel(
                locator: locator,
                installer: installer,
                settingsProvider: { HelperToolSettings() }
            )

            model.refresh()
            for bundle in HelperToolBundle.allCases {
                XCTAssertTrue(installer.isInstalled(bundle))
                XCTAssertEqual(model.states[bundle], .installed)
            }
            XCTAssertTrue(model.allInstalled)
        }
    }

    func testDownloadAndConvertSuccessInstallsThreeExecutables() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        let collector = ProgressCollector()
        try await installer.install(.downloadAndConvert) { value in
            collector.append(value)
        }

        for tool in HelperToolBundle.downloadAndConvert.tools {
            let url = locator.managedExecutableURL(for: tool)
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: url.path),
                "Missing executable for \(tool.executableName)"
            )
            XCTAssertEqual(try posixPermissions(of: url), 0o755)
        }
        XCTAssertTrue(installer.isInstalled(.downloadAndConvert))
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testFfmpegChecksumMismatchLeavesExistingBinUntouched() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader, badFfmpegChecksum: true)

        let bin = locator.managedBinDirectory
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let existing = bin.appendingPathComponent("ffmpeg", isDirectory: false)
        let original = Data("original-ffmpeg-bytes".utf8)
        try original.write(to: existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: existing.path)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.downloadAndConvert) { _ in }
            XCTFail("Expected checksumMismatch")
        } catch let error as HelperInstallError {
            XCTAssertEqual(error, .checksumMismatch(file: "FFmpeg"))
        }
        XCTAssertEqual(try Data(contentsOf: existing), original)
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testFfmpegChecksumFetchedFromFinalURL() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        let finals = seedDownloadAndConvert(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        try await installer.install(.downloadAndConvert) { _ in }

        let expectedFfmpeg = URL(string: finals.ffmpeg.absoluteString + ".sha256")!
        let expectedFfprobe = URL(string: finals.ffprobe.absoluteString + ".sha256")!
        XCTAssertTrue(downloader.textRequests.contains(expectedFfmpeg))
        XCTAssertTrue(downloader.textRequests.contains(expectedFfprobe))
    }

    func testStemSeparationPassesExactUvArgumentsAndEnvironment() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedStemSeparation(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        try await installer.install(.stemSeparation) { _ in }

        let uvRequests = runner.requests.filter {
            $0.executableURL.lastPathComponent == "uv" && $0.arguments.first == "tool"
        }
        XCTAssertEqual(uvRequests.count, 1)
        let uvRequest = try XCTUnwrap(uvRequests.first)
        XCTAssertEqual(
            uvRequest.arguments,
            ["tool", "install", "--upgrade", "--python", "3.12", "demucs-mlx[convert]"]
        )
        XCTAssertEqual(uvRequest.timeoutSeconds, 1800)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let attemptBin = URL(fileURLWithPath: try XCTUnwrap(uvRequest.environment?["UV_TOOL_BIN_DIR"]))
        let attemptRoot = attemptBin.deletingLastPathComponent()
        XCTAssertEqual(attemptRoot.deletingLastPathComponent().path, managedRoot.appendingPathComponent("uv-tools").path)
        XCTAssertNotEqual(attemptBin.path, locator.managedBinDirectory.path)
        XCTAssertEqual(uvRequest.environment, [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "UV_TOOL_DIR": attemptRoot.appendingPathComponent("tools").path,
            "UV_TOOL_BIN_DIR": attemptBin.path,
            "UV_PYTHON_INSTALL_DIR": attemptRoot.appendingPathComponent("python").path,
            "UV_CACHE_DIR": attemptRoot.appendingPathComponent("cache").path,
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
        ])

        let demucsBin = locator.managedExecutableURL(for: .demucsMlx)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: demucsBin.path))
        let uvBin = managedRoot.appendingPathComponent("uv/uv")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: uvBin.path))

        let warmups = runner.requests.filter {
            $0.executableURL.path == attemptBin.appendingPathComponent("demucs-mlx").path
        }
        XCTAssertEqual(warmups.count, 1)
        let warmup = try XCTUnwrap(warmups.first)
        XCTAssertEqual(warmup.timeoutSeconds, 1800)
        XCTAssertEqual(warmup.environment?["PATH"], "\(attemptBin.path):\(locator.managedBinDirectory.path):/usr/bin:/bin")
        XCTAssertNotNil(warmup.environment?["HOME"], "warm-up must use the same HOME as later runs")
        XCTAssertTrue(warmup.arguments.contains("-n"))
        XCTAssertTrue(warmup.arguments.contains("htdemucs_ft"))
        let outputIndex = try XCTUnwrap(warmup.arguments.firstIndex(of: "--out"))
        XCTAssertTrue(warmup.arguments[outputIndex + 1].hasPrefix(attemptRoot.path + "/"))
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testStemInstallRemovesLeftoverStagingAndSupersededEnvironments() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        seedStemSeparation(downloader: downloader)
        let uvTools = managedRoot.appendingPathComponent("uv-tools", isDirectory: true)
        let orphanStaging = managedRoot.appendingPathComponent(".staging/orphan", isDirectory: true)
        let orphanEnvironment = uvTools.appendingPathComponent("orphan", isDirectory: true)
        for directory in [orphanStaging, orphanEnvironment] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let installer = HelperToolInstaller(locator: locator, downloader: downloader, processRunner: FakeRunner())
        try await installer.install(.stemSeparation) { _ in }
        let first = try FileManager.default.contentsOfDirectory(atPath: uvTools.path)
        XCTAssertEqual(first.count, 1, "uv-tools: \(first)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanEnvironment.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanStaging.path))

        try await installer.install(.stemSeparation) { _ in }
        let second = try FileManager.default.contentsOfDirectory(atPath: uvTools.path)
        XCTAssertEqual(second.count, 1, "uv-tools: \(second)")
        XCTAssertNotEqual(second, first, "The superseded environment must be removed")
        XCTAssertTrue(installer.isInstalled(.stemSeparation))
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testUvNonzeroExitThrowsSetupFailedAndKeepsExistingDemucs() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        runner.uvExitCode = 1
        runner.uvStderr = "boom-failure"
        seedStemSeparation(downloader: downloader)

        let bin = locator.managedBinDirectory
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let existing = bin.appendingPathComponent("demucs-mlx", isDirectory: false)
        let original = Data("original-demucs-bytes".utf8)
        try original.write(to: existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: existing.path)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.stemSeparation) { _ in }
            XCTFail("Expected setupFailed")
        } catch let error as HelperInstallError {
            guard case let .setupFailed(detail) = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
            XCTAssertTrue(detail.contains("demucs-mlx"))
        }
        XCTAssertEqual(try Data(contentsOf: existing), original)
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testProgressFractionsAreNonDecreasingAndEndAtOne() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        let collector = ProgressCollector()
        try await installer.install(.downloadAndConvert) { value in
            collector.append(value)
        }

        let values = collector.values
        XCTAssertFalse(values.isEmpty)
        let fractions = values.compactMap(\.fractionCompleted)
        XCTAssertEqual(fractions.count, values.count)
        for index in 1..<fractions.count {
            XCTAssertGreaterThanOrEqual(
                fractions[index], fractions[index - 1],
                "Fractions decreased at index \(index)"
            )
        }
        XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(values.last?.phase, "Done")
    }

    func testCancellationDuringDownloadThrowsAndLeavesNoStaging() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader)
        downloader.hang(url: HelperToolDownloadSources.ytDlpBinary)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        let task = Task {
            try await installer.install(.downloadAndConvert) { _ in }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testCancelledStemAttemptPreservesExistingAndNewerHelpers() async throws {
        for phase in StemSetupGateRunner.Phase.allCases {
            for (existing, replace) in [(false, false), (true, false), (false, true), (true, true)] {
                let root = try makeTempRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let locator = HelperToolLocator(managedRoot: root, systemDirectories: [])
                let target = locator.managedExecutableURL(for: .demucsMlx)
                let original = Data("#!/bin/sh\n# original\nexit 0\n".utf8)
                if existing {
                    try FileManager.default.createDirectory(at: locator.managedBinDirectory, withIntermediateDirectories: true)
                    try original.write(to: target)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                }
                let runner = StemSetupGateRunner(phase: phase, checksCancellation: existing)
                let installer = HelperToolInstaller(locator: locator, downloader: ChecksummedSetupDownloader(), processRunner: runner)
                let cancelled = Task { try await installer.install(.stemSeparation) { _ in } }
                await runner.waitUntilReached()
                XCTAssertEqual(installer.isInstalled(.stemSeparation), existing)
                cancelled.cancel()
                if existing { XCTAssertEqual(try Data(contentsOf: target), original) }
                if replace {
                    // The old attempt is still unwinding when its replacement succeeds.
                    try await installer.install(.stemSeparation) { _ in }
                }
                let replacement = existing || replace ? try Data(contentsOf: target) : nil
                await runner.release()
                do {
                    try await cancelled.value
                    XCTFail("Expected CancellationError")
                } catch is CancellationError {}
                try await runner.simulateLateWrite()
                XCTAssertEqual(installer.isInstalled(.stemSeparation), existing || replace)
                if let replacement { XCTAssertEqual(try Data(contentsOf: target), replacement) }
                assertNoStagingLeft(managedRoot: root)
            }
        }
    }

    /// T16 (ADR-019): an install is quit-blocking work while it runs, whether
    /// it finishes or quit cancels it; the cancel still removes staging.
    @MainActor
    func testRunningInstallRegistersBlockingWorkUntilFinishedOrCancelled() async throws {
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            seedDownloadAndConvert(downloader: downloader)
            downloader.hang(url: HelperToolDownloadSources.ytDlpBinary)
            let center = ShellJobStatusCenter(jobRunner: JobRunner())
            let model = HelperToolSetupModel(
                locator: locator,
                installer: HelperToolInstaller(locator: locator, downloader: downloader, processRunner: FakeRunner()),
                settingsProvider: { HelperToolSettings() },
                jobStatusCenter: center
            )

            model.install(.downloadAndConvert)
            let work = center.quitBlockingWork
            XCTAssertEqual(work.map(\.id), [ShellJobExtraSourceID.helperInstall.rawValue])
            XCTAssertEqual(work.first?.listed, false)
            XCTAssertTrue(center.jobs.isEmpty, "Installs show their progress in Set Up, not in the jobs strip")
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(center.hasUnfinishedQuitBlockingWork)

            center.cancelAllForQuit()
            try await waitUntilQuitWorkDrains(center)
            XCTAssertFalse(model.isInstalling)
            assertNoStagingLeft(managedRoot: managedRoot)
        }
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            seedDownloadAndConvert(downloader: downloader)
            let center = ShellJobStatusCenter(jobRunner: JobRunner())
            let model = HelperToolSetupModel(
                locator: locator,
                installer: HelperToolInstaller(locator: locator, downloader: downloader, processRunner: FakeRunner()),
                settingsProvider: { HelperToolSettings() },
                jobStatusCenter: center
            )

            model.install(.downloadAndConvert)
            XCTAssertTrue(center.hasUnfinishedQuitBlockingWork)
            try await waitUntilQuitWorkDrains(center)
            XCTAssertEqual(model.states[.downloadAndConvert], .installed)
            XCTAssertTrue(center.quitBlockingWork.isEmpty)
        }
    }

    func testFfprobeDownloadFailureLeavesManagedBinUntouched() async throws {
        // Pre-existing ffmpeg must stay byte-identical.
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            let runner = FakeRunner()
            seedOnlyYtAndFfmpeg(downloader: downloader)

            let bin = locator.managedBinDirectory
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let existing = bin.appendingPathComponent("ffmpeg", isDirectory: false)
            let original = Data("original-ffmpeg-bytes".utf8)
            try original.write(to: existing)

            let installer = HelperToolInstaller(
                locator: locator,
                downloader: downloader,
                processRunner: runner
            )
            do {
                try await installer.install(.downloadAndConvert) { _ in }
                XCTFail("Expected downloadFailed")
            } catch let error as HelperInstallError {
                guard case .downloadFailed = error else {
                    XCTFail("Wrong error: \(error)")
                    return
                }
            }
            XCTAssertEqual(try Data(contentsOf: existing), original)
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: bin.appendingPathComponent("yt-dlp").path
            ))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: bin.appendingPathComponent("ffprobe").path
            ))
            assertNoStagingLeft(managedRoot: managedRoot)
        }

        // No pre-existing ffmpeg: nothing may be published.
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            let runner = FakeRunner()
            seedOnlyYtAndFfmpeg(downloader: downloader)

            let installer = HelperToolInstaller(
                locator: locator,
                downloader: downloader,
                processRunner: runner
            )
            do {
                try await installer.install(.downloadAndConvert) { _ in }
                XCTFail("Expected downloadFailed")
            } catch let error as HelperInstallError {
                guard case .downloadFailed = error else {
                    XCTFail("Wrong error: \(error)")
                    return
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: locator.managedExecutableURL(for: .ffmpeg).path
            ))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: locator.managedExecutableURL(for: .ytDlp).path
            ))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: locator.managedExecutableURL(for: .ffprobe).path
            ))
            assertNoStagingLeft(managedRoot: managedRoot)
        }
    }

    func testDittoNonZeroExitThrowsExtractFailedAndLeavesBinUntouched() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader)
        runner.dittoExitCode = 1
        runner.dittoStderr = "ditto failed boom\nsecond line"

        let bin = locator.managedBinDirectory
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let existing = bin.appendingPathComponent("ffmpeg", isDirectory: false)
        let original = Data("original-ffmpeg-bytes".utf8)
        try original.write(to: existing)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.downloadAndConvert) { _ in }
            XCTFail("Expected extractFailed")
        } catch let error as HelperInstallError {
            guard case let .extractFailed(detail) = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
            XCTAssertTrue(detail.contains("FFmpeg"), "detail: \(detail)")
            XCTAssertTrue(detail.contains("ditto failed boom"), "detail: \(detail)")
        }
        XCTAssertEqual(try Data(contentsOf: existing), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: bin.appendingPathComponent("yt-dlp").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: bin.appendingPathComponent("ffprobe").path
        ))
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testTarNonZeroExitThrowsExtractFailed() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedStemSeparation(downloader: downloader)
        runner.tarExitCode = 1
        runner.tarStderr = "tar exploded"

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.stemSeparation) { _ in }
            XCTFail("Expected extractFailed")
        } catch let error as HelperInstallError {
            guard case let .extractFailed(detail) = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
            XCTAssertTrue(detail.contains("uv"), "detail: \(detail)")
            XCTAssertTrue(detail.contains("tar exploded"), "detail: \(detail)")
        }
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testVerificationRunsFromStagingBinIncludingFfprobe() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        seedDownloadAndConvert(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        try await installer.install(.downloadAndConvert) { _ in }

        let managedBinPath = locator.managedBinDirectory.path
        let ytChecks = runner.requests.filter { $0.arguments == ["--version"] }
        let ffmpegChecks = runner.requests.filter {
            $0.arguments == ["-version"] && $0.executableURL.lastPathComponent == "ffmpeg"
        }
        let ffprobeChecks = runner.requests.filter {
            $0.arguments == ["-version"] && $0.executableURL.lastPathComponent == "ffprobe"
        }
        XCTAssertEqual(ytChecks.count, 1)
        XCTAssertEqual(ffmpegChecks.count, 1)
        XCTAssertEqual(ffprobeChecks.count, 1)

        for request in ytChecks + ffmpegChecks + ffprobeChecks {
            XCTAssertTrue(
                request.executableURL.path.contains(".staging"),
                "Verification must run from staging bin, got \(request.executableURL.path)"
            )
            XCTAssertTrue(
                request.executableURL.path.contains("/bin/"),
                "Verification must run from staging bin, got \(request.executableURL.path)"
            )
            XCTAssertFalse(
                request.executableURL.path.hasPrefix(managedBinPath + "/"),
                "Verification must not run from managed bin, got \(request.executableURL.path)"
            )
        }
        let ffprobeRequest = try XCTUnwrap(ffprobeChecks.first)
        XCTAssertEqual(ffprobeRequest.timeoutSeconds, 30)
        let ffmpegRequest = try XCTUnwrap(ffmpegChecks.first)
        XCTAssertEqual(ffmpegRequest.timeoutSeconds, 30)
    }

    func testUnexpectedDownloadHostRejectsBeforeChecksumFetch() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()

        let ytData = Data("fake-yt-dlp-binary".utf8)
        downloader.serve(data: ytData, for: HelperToolDownloadSources.ytDlpBinary)
        downloader.serve(
            text: "\(sha256Hex(ytData))  yt-dlp_macos\n",
            for: HelperToolDownloadSources.ytDlpChecksums
        )
        let ffmpegData = Data("fake-ffmpeg-zip-bytes".utf8)
        let evilFinal = URL(string: "https://evil.example.com/final/ffmpeg.zip")!
        downloader.serve(data: ffmpegData, for: HelperToolDownloadSources.ffmpegZip, finalURL: evilFinal)
        let evilChecksum = URL(string: evilFinal.absoluteString + ".sha256")!
        downloader.serve(text: "\(sha256Hex(ffmpegData))  ffmpeg.zip\n", for: evilChecksum)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.downloadAndConvert) { _ in }
            XCTFail("Expected downloadFailed")
        } catch let error as HelperInstallError {
            guard case let .downloadFailed(detail) = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
            XCTAssertTrue(detail.contains("unexpected download host"), "detail: \(detail)")
            XCTAssertTrue(detail.contains("evil.example.com"), "detail: \(detail)")
        }
        XCTAssertFalse(
            downloader.textRequests.contains(evilChecksum),
            "Checksum URL must never be fetched for an unexpected host"
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: locator.managedExecutableURL(for: .ffmpeg).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: locator.managedExecutableURL(for: .ytDlp).path
        ))
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testUvFailureWithNoPreExistingDemucsRemovesStrayLink() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let downloader = FakeDownloader()
        let runner = FakeRunner()
        runner.uvExitCode = 1
        runner.uvStderr = "boom-failure"
        seedStemSeparation(downloader: downloader)

        let installer = HelperToolInstaller(
            locator: locator,
            downloader: downloader,
            processRunner: runner
        )
        do {
            try await installer.install(.stemSeparation) { _ in }
            XCTFail("Expected setupFailed")
        } catch let error as HelperInstallError {
            guard case .setupFailed = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locator.managedExecutableURL(for: .demucsMlx).path),
            "Stray demucs-mlx from the failed run must be removed when none existed before"
        )
        assertNoStagingLeft(managedRoot: managedRoot)
    }

    func testWarmupFailureRemovesOnlyNewDemucs() async throws {
        // No pre-existing: stray link removed.
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            let runner = FakeRunner()
            runner.warmupExitCode = 1
            runner.warmupStderr = "warmup boom"
            seedStemSeparation(downloader: downloader)

            let installer = HelperToolInstaller(
                locator: locator,
                downloader: downloader,
                processRunner: runner
            )
            do {
                try await installer.install(.stemSeparation) { _ in }
                XCTFail("Expected verificationFailed")
            } catch let error as HelperInstallError {
                guard case .verificationFailed = error else {
                    XCTFail("Wrong error: \(error)")
                    return
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: locator.managedExecutableURL(for: .demucsMlx).path
            ))
            assertNoStagingLeft(managedRoot: managedRoot)
        }

        // Failed preparation preserves the original executable byte-for-byte.
        do {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
            let downloader = FakeDownloader()
            let runner = FakeRunner()
            runner.warmupExitCode = 1
            runner.warmupStderr = "warmup boom"
            seedStemSeparation(downloader: downloader)

            // A pre-existing tool remains available throughout preparation.
            let bin = locator.managedBinDirectory
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let existing = bin.appendingPathComponent("demucs-mlx", isDirectory: false)
            let original = Data("original-demucs-bytes".utf8)
            try original.write(to: existing)
            let installer = HelperToolInstaller(
                locator: locator,
                downloader: downloader,
                processRunner: runner
            )
            do {
                try await installer.install(.stemSeparation) { _ in }
                XCTFail("Expected verificationFailed")
            } catch let error as HelperInstallError {
                guard case .verificationFailed = error else {
                    XCTFail("Wrong error: \(error)")
                    return
                }
            }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: existing.path),
                "Pre-existing demucs-mlx must never be deleted"
            )
            XCTAssertEqual(try Data(contentsOf: existing), original)
            assertNoStagingLeft(managedRoot: managedRoot)
        }
    }

    // MARK: - Seeding

    @discardableResult
    private func seedDownloadAndConvert(
        downloader: FakeDownloader,
        badFfmpegChecksum: Bool = false
    ) -> (ffmpeg: URL, ffprobe: URL) {
        let ytData = Data("fake-yt-dlp-binary".utf8)
        downloader.serve(data: ytData, for: HelperToolDownloadSources.ytDlpBinary)
        downloader.serve(
            text: "\(sha256Hex(ytData))  yt-dlp_macos\n",
            for: HelperToolDownloadSources.ytDlpChecksums
        )

        let ffmpegData = Data("fake-ffmpeg-zip-bytes".utf8)
        let ffmpegFinal = URL(
            string: "https://\(HelperToolDownloadSources.ffmpegHost)/final/ffmpeg.zip"
        )!
        downloader.serve(data: ffmpegData, for: HelperToolDownloadSources.ffmpegZip, finalURL: ffmpegFinal)
        let ffmpegHash = badFfmpegChecksum ? String(repeating: "0", count: 64) : sha256Hex(ffmpegData)
        downloader.serve(
            text: "\(ffmpegHash)  ffmpeg.zip\n",
            for: URL(string: ffmpegFinal.absoluteString + ".sha256")!
        )

        let ffprobeData = Data("fake-ffprobe-zip-bytes".utf8)
        let ffprobeFinal = URL(
            string: "https://\(HelperToolDownloadSources.ffmpegHost)/final/ffprobe.zip"
        )!
        downloader.serve(data: ffprobeData, for: HelperToolDownloadSources.ffprobeZip, finalURL: ffprobeFinal)
        downloader.serve(
            text: "\(sha256Hex(ffprobeData))  ffprobe.zip\n",
            for: URL(string: ffprobeFinal.absoluteString + ".sha256")!
        )
        return (ffmpegFinal, ffprobeFinal)
    }

    private func seedStemSeparation(downloader: FakeDownloader) {
        let uvData = Data("fake-uv-archive".utf8)
        downloader.serve(data: uvData, for: HelperToolDownloadSources.uvArchive)
        downloader.serve(
            text: "\(sha256Hex(uvData))  uv-aarch64-apple-darwin.tar.gz\n",
            for: HelperToolDownloadSources.uvChecksum
        )
    }

    private func seedOnlyYtAndFfmpeg(downloader: FakeDownloader) {
        let ytData = Data("fake-yt-dlp-binary".utf8)
        downloader.serve(data: ytData, for: HelperToolDownloadSources.ytDlpBinary)
        downloader.serve(
            text: "\(sha256Hex(ytData))  yt-dlp_macos\n",
            for: HelperToolDownloadSources.ytDlpChecksums
        )
        let ffmpegData = Data("fake-ffmpeg-zip-bytes".utf8)
        let ffmpegFinal = URL(
            string: "https://\(HelperToolDownloadSources.ffmpegHost)/final/ffmpeg.zip"
        )!
        downloader.serve(data: ffmpegData, for: HelperToolDownloadSources.ffmpegZip, finalURL: ffmpegFinal)
        downloader.serve(
            text: "\(sha256Hex(ffmpegData))  ffmpeg.zip\n",
            for: URL(string: ffmpegFinal.absoluteString + ".sha256")!
        )
        // Intentionally no ffprobe payload: the ffprobe download throws downloadFailed.
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntilQuitWorkDrains(_ center: ShellJobStatusCenter) async throws {
        for _ in 0..<200 {
            if !center.hasUnfinishedQuitBlockingWork { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the install to leave the quit registry")
    }

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("HelperToolInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func posixPermissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func assertNoStagingLeft(managedRoot: URL, file: StaticString = #filePath, line: UInt = #line) {
        let stagingRoot = managedRoot.appendingPathComponent(".staging", isDirectory: true)
        guard FileManager.default.fileExists(atPath: stagingRoot.path) else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: stagingRoot.path)) ?? []
        XCTAssertTrue(contents.isEmpty, "Staging not cleaned: \(contents)", file: file, line: line)
    }
}

private final class FakeDownloader: HelperDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var dataByURL: [String: Data] = [:]
    private var textByURL: [String: String] = [:]
    private var finalByURL: [String: URL] = [:]
    private var hanging: Set<String> = []
    private var downloadRequestsStorage: [URL] = []
    private var textRequestsStorage: [URL] = []

    var downloadRequests: [URL] {
        lock.withLock { downloadRequestsStorage }
    }

    var textRequests: [URL] {
        lock.withLock { textRequestsStorage }
    }

    func serve(data: Data, for url: URL, finalURL: URL? = nil) {
        lock.withLock {
            dataByURL[url.absoluteString] = data
            if let finalURL {
                finalByURL[url.absoluteString] = finalURL
            }
        }
    }

    func serve(text: String, for url: URL) {
        lock.withLock {
            textByURL[url.absoluteString] = text
        }
    }

    func hang(url: URL) {
        lock.withLock {
            _ = hanging.insert(url.absoluteString)
        }
    }

    func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        lock.withLock {
            downloadRequestsStorage.append(url)
        }
        let isHanging = lock.withLock { hanging.contains(url.absoluteString) }
        if isHanging {
            try await Task.sleep(for: .seconds(30))
            try Task.checkCancellation()
            throw CancellationError()
        }
        progress(0.5)
        try Task.checkCancellation()
        guard let payload = lock.withLock({ dataByURL[url.absoluteString] }) else {
            throw HelperInstallError.downloadFailed(url.lastPathComponent)
        }
        try FileManager.default.createDirectory(
            at: destinationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: destinationFile)
        progress(1.0)
        return lock.withLock { finalByURL[url.absoluteString] } ?? url
    }

    func fetchText(_ url: URL) async throws -> String {
        lock.withLock {
            textRequestsStorage.append(url)
        }
        if let text = lock.withLock({ textByURL[url.absoluteString] }) {
            return text
        }
        if let data = lock.withLock({ dataByURL[url.absoluteString] }),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        throw HelperInstallError.downloadFailed(url.lastPathComponent)
    }
}

private final class FakeRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var requestsStorage: [ExternalProcessRequest] = []
    var uvExitCode: Int32 = 0
    var uvStderr = ""
    var dittoExitCode: Int32 = 0
    var dittoStderr = ""
    var tarExitCode: Int32 = 0
    var tarStderr = ""
    var warmupExitCode: Int32 = 0
    var warmupStderr = ""

    var requests: [ExternalProcessRequest] {
        lock.withLock { requestsStorage }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        lock.withLock {
            requestsStorage.append(request)
        }
        try Task.checkCancellation()
        let manager = FileManager.default
        let executablePath = request.executableURL.path
        let arguments = request.arguments

        if executablePath == "/usr/bin/ditto" {
            if dittoExitCode != 0 {
                return ExternalProcessResult(
                    exitCode: dittoExitCode,
                    standardOutput: "",
                    standardError: dittoStderr.isEmpty ? "ditto failed" : dittoStderr
                )
            }
            guard arguments.count >= 4 else {
                return ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad ditto args")
            }
            let zipPath = arguments[arguments.count - 2]
            let destinationPath = arguments[arguments.count - 1]
            let stem = URL(fileURLWithPath: zipPath).deletingPathExtension().lastPathComponent
            let destination = URL(fileURLWithPath: destinationPath, isDirectory: true)
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            let output = destination.appendingPathComponent(stem, isDirectory: false)
            try "#!/bin/sh\nexit 0\n".write(to: output, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        if executablePath == "/usr/bin/tar" {
            if tarExitCode != 0 {
                return ExternalProcessResult(
                    exitCode: tarExitCode,
                    standardOutput: "",
                    standardError: tarStderr.isEmpty ? "tar failed" : tarStderr
                )
            }
            guard let flagIndex = arguments.firstIndex(of: "-C"),
                  flagIndex + 1 < arguments.count
            else {
                return ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad tar args")
            }
            let destination = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
            let nested = destination.appendingPathComponent("uv-aarch64-apple-darwin", isDirectory: true)
            try manager.createDirectory(at: nested, withIntermediateDirectories: true)
            let output = nested.appendingPathComponent("uv", isDirectory: false)
            try "#!/bin/sh\nexit 0\n".write(to: output, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        if request.executableURL.lastPathComponent == "uv" {
            if uvExitCode != 0 {
                // Simulate a stray link left behind by a failed uv run when none
                // existed before; leave a pre-existing file untouched.
                if let binDir = request.environment?["UV_TOOL_BIN_DIR"] {
                    let output = URL(fileURLWithPath: binDir, isDirectory: true)
                        .appendingPathComponent("demucs-mlx", isDirectory: false)
                    if !manager.fileExists(atPath: output.path) {
                        try? manager.createDirectory(
                            at: URL(fileURLWithPath: binDir, isDirectory: true),
                            withIntermediateDirectories: true
                        )
                        try? "#!/bin/sh\nexit 0\n".write(to: output, atomically: true, encoding: .utf8)
                        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
                    }
                }
                return ExternalProcessResult(
                    exitCode: uvExitCode,
                    standardOutput: "",
                    standardError: uvStderr
                )
            }
            if let binDir = request.environment?["UV_TOOL_BIN_DIR"] {
                let binURL = URL(fileURLWithPath: binDir, isDirectory: true)
                try manager.createDirectory(at: binURL, withIntermediateDirectories: true)
                let output = binURL.appendingPathComponent("demucs-mlx", isDirectory: false)
                try "#!/bin/sh\nexit 0\n".write(to: output, atomically: true, encoding: .utf8)
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
            }
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        if executablePath.hasSuffix("demucs-mlx") {
            if warmupExitCode != 0 {
                return ExternalProcessResult(
                    exitCode: warmupExitCode,
                    standardOutput: "",
                    standardError: warmupStderr.isEmpty ? "warmup failed" : warmupStderr
                )
            }
            return ExternalProcessResult(exitCode: 0, standardOutput: "test-1.0", standardError: "")
        }

        if arguments.contains("--version") || arguments.contains("-version") {
            return ExternalProcessResult(exitCode: 0, standardOutput: "test-1.0", standardError: "")
        }

        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

/// Holds the first uv publication or warmup until the test releases teardown.
actor StemSetupGateRunner: StreamingExternalProcessRunning {
    enum Phase: CaseIterable, Equatable { case uv, warmup }
    private let phase: Phase?
    private let checksCancellation: Bool
    private let base = FakeRunner()
    private var reached = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var suspended: CheckedContinuation<Void, Never>?
    private var firstBin: URL?

    init(phase: Phase? = nil, checksCancellation: Bool = true) {
        self.phase = phase
        self.checksCancellation = checksCancellation
    }

    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() { suspended?.resume(); suspended = nil }

    func simulateLateWrite() throws {
        guard let firstBin else { return }
        try FileManager.default.createDirectory(at: firstBin, withIntermediateDirectories: true)
        let executable = firstBin.appendingPathComponent("demucs-mlx")
        try "#!/bin/sh\n# cancelled writer\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        let result = try await base.run(request, onStandardOutput: onStandardOutput, onStandardError: onStandardError)
        if firstBin == nil, let path = request.environment?["UV_TOOL_BIN_DIR"] {
            firstBin = URL(fileURLWithPath: path, isDirectory: true)
        }
        let step: Phase? = request.arguments.first == "tool" ? .uv
            : request.executableURL.lastPathComponent == "demucs-mlx" ? .warmup : nil
        if let phase, step == phase, !reached {
            await withCheckedContinuation { continuation in
                suspended = continuation
                reached = true
                waiter?.resume(); waiter = nil
            }
            if checksCancellation { try Task.checkCancellation() }
        }
        return result
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HelperInstallProgress] = []

    func append(_ value: HelperInstallProgress) {
        lock.withLock {
            storage.append(value)
        }
    }

    var values: [HelperInstallProgress] {
        lock.withLock { storage }
    }
}
