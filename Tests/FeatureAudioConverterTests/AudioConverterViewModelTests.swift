import AppCore
import Combine
import FeatureAudioConverter
import XCTest

@MainActor
final class AudioConverterViewModelTests: XCTestCase {
    func testQueuedAndUnsupportedRowsAreCreatedFromScanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let audio = try makeFile(named: "Loop.m4a", in: directory)
        let text = try makeFile(named: "Notes.txt", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)

        viewModel.addFileURLs([audio, text])

        XCTAssertEqual(viewModel.rows.map(\.state), [.queued, .unsupported])
        XCTAssertEqual(viewModel.rows[0].statusText, "Queued")
        XCTAssertEqual(
            viewModel.rows[1].statusText,
            "This file type is not supported. Add M4A, MP3, WAV, AIFF, or FLAC instead."
        )
        XCTAssertFalse(viewModel.rows[1].statusText.contains("Phase"))
        XCTAssertEqual(viewModel.rows[0].plannedOutputName, "Loop - 44100Hz 24bit.wav")
    }

    func testAddRemoveDedupeAndNoticeCap() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = try [
            makeFile(named: "Track1.m4a", in: directory),
            makeFile(named: "Track2.mp3", in: directory),
            makeFile(named: "Track3.wav", in: directory),
            makeFile(named: "Track4.aiff", in: directory),
            makeFile(named: "Track5.flac", in: directory),
        ]
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.addFileURLs(files)
        XCTAssertEqual(viewModel.rows.count, 5)

        viewModel.removeRow(id: viewModel.rows[0].id)
        viewModel.removeRow(id: viewModel.rows[0].id)
        XCTAssertEqual(viewModel.rows.count, 3)

        let remaining = try XCTUnwrap(viewModel.rows.first?.sourceURL)
        viewModel.addFileURLs([remaining])
        XCTAssertEqual(viewModel.rows.count, 3, "Re-adding a batched URL must not duplicate the row")
        XCTAssertEqual(viewModel.rows.filter { $0.sourceURL == remaining }.count, 1)

        for index in 1...12 {
            let folder = directory.appendingPathComponent("NoticeFolder\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("Sub", isDirectory: true),
                withIntermediateDirectories: true
            )
            viewModel.addFileURLs([folder])
            if index == 1 {
                XCTAssertEqual(viewModel.notices.count, 1)
            }
            if index == 2 {
                XCTAssertEqual(viewModel.notices.count, 2, "Notices must append rather than replace")
            }
        }
        XCTAssertEqual(viewModel.notices.count, 10, "Notices must cap at 10 lines")
        XCTAssertEqual(viewModel.rows.count, 3, "Notice-only folders must not add rows")

        viewModel.clearAll()
        XCTAssertTrue(viewModel.rows.isEmpty, "Clear All empties the list when idle")
    }

    func testRouterHandoffQueuesFilesWhileSessionIsAlreadyBound() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preview = try makeFile(named: "Preview.wav", in: directory)
        let router = QuickAccessRouter()
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.bindConverterHandoff(to: router)
        XCTAssertTrue(viewModel.rows.isEmpty)

        // Simulates Archive → "Convert preview" after the converter pane was already visited.
        router.openConverter(with: [preview])
        await drainMainQueue()

        XCTAssertEqual(viewModel.rows.map(\.sourceURL), [preview])
        XCTAssertEqual(viewModel.rows.map(\.state), [.queued])
        XCTAssertTrue(router.prefilledConverterURLs.isEmpty, "handoff must be consumed exactly once")

        // A second handoff for the same session queues again instead of being dropped.
        let second = try makeFile(named: "Second.m4a", in: directory)
        router.openConverter(with: [second])
        await drainMainQueue()

        XCTAssertEqual(viewModel.rows.map(\.sourceURL), [preview, second])
    }

    func testRouterHandoffPendingBeforeBindIsDrainedOnBind() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preview = try makeFile(named: "Preview.wav", in: directory)
        let router = QuickAccessRouter()
        router.openConverter(with: [preview])

        // Simulates the first visit: the session is created after the handoff was requested.
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.bindConverterHandoff(to: router)
        await drainMainQueue()

        XCTAssertEqual(viewModel.rows.map(\.sourceURL), [preview])
        XCTAssertTrue(router.prefilledConverterURLs.isEmpty)
    }

    func testBindConverterHandoffDoesNotPublishContinuously() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let router = QuickAccessRouter()
        let viewModel = makeViewModel(outputFolder: directory)
        let counter = EmissionCounter()
        let cancellable = router.$prefilledConverterURLs.dropFirst().sink { _ in counter.increment() }
        defer { cancellable.cancel() }

        viewModel.bindConverterHandoff(to: router)

        // Spin the main queue/run loop ~0.3 s. Old code republishes continuously here.
        let deadline = Date(timeIntervalSinceNow: 0.3)
        while Date() < deadline {
            await drainMainQueue()
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertLessThanOrEqual(
            counter.count,
            2,
            "bind with no handoff must stay quiet, got \(counter.count) emissions"
        )
        XCTAssertTrue(viewModel.rows.isEmpty)

        // A later handoff still arrives exactly once.
        let fixture = try makeFile(named: "Handoff.wav", in: directory)
        router.openConverter(with: [fixture])
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(viewModel.rows.map(\.sourceURL), [fixture])
        XCTAssertTrue(router.prefilledConverterURLs.isEmpty, "handoff must be consumed exactly once")
    }

    func testConvertButtonDisabledWithoutQueuedRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let unsupported = try makeFile(named: "Notes.txt", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)

        XCTAssertFalse(viewModel.canConvertToWAV)
        viewModel.addFileURLs([unsupported])

        XCTAssertFalse(viewModel.canConvertToWAV)
    }

    func testMissingHelperCopyMatchesUISpec() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([source])

        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(viewModel.rows.first?.state, .failed)
        XCTAssertEqual(
            viewModel.rows.first?.statusText,
            "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
        )
        XCTAssertEqual(viewModel.rows.first?.recoveryActionTitle, "Choose FFmpeg")
    }

    func testChooseFFmpegPersistsHelperAndRequeuesRow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let ffmpegURL = try makeFile(named: "ffmpeg", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let healthChecker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(
                    exitCode: 0,
                    standardOutput: "ffmpeg version 8.1",
                    standardError: ""
                )
            )),
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { $0 == ffmpegURL.path }
            )
        )
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore,
            ffmpegHealthChecker: healthChecker
        )
        viewModel.addFileURLs([source])
        _ = await viewModel.convertQueuedRows()
        let rowID = try XCTUnwrap(viewModel.rows.first?.id)

        await viewModel.chooseFFmpegAndRetry(rowID: rowID, ffmpegURL: ffmpegURL)

        XCTAssertEqual(settingsStore.settings.helperTools.ffmpeg, ffmpegURL)
        XCTAssertEqual(viewModel.rows.first?.state, .queued)
        XCTAssertNil(viewModel.rows.first?.recoveryActionTitle)
    }

    func testChooseFFmpegKeepsRowFailedWhenHelperIsUnusable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let ffmpegURL = try makeFile(named: "ffmpeg", in: directory)
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let healthChecker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad helper")
            )),
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { $0 == ffmpegURL.path }
            )
        )
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            ffmpegHealthChecker: healthChecker
        )
        viewModel.addFileURLs([source])
        _ = await viewModel.convertQueuedRows()
        let rowID = try XCTUnwrap(viewModel.rows.first?.id)

        await viewModel.chooseFFmpegAndRetry(rowID: rowID, ffmpegURL: ffmpegURL)

        XCTAssertEqual(viewModel.rows.first?.state, .failed)
        XCTAssertEqual(viewModel.rows.first?.recoveryActionTitle, "Choose FFmpeg")
        XCTAssertEqual(viewModel.rows.first?.statusText, "Selected FFmpeg could not be used: bad helper")
    }

    func testStopAfterCurrentStateHandoff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeFile(named: "First.wav", in: directory)
        let second = try makeFile(named: "Second.wav", in: directory)
        var viewModel: AudioConverterViewModel!
        let converter = RecordingViewModelConverter { request in
            if request.sourceURL == first {
                await MainActor.run {
                    viewModel.requestStopAfterCurrent()
                }
            }
            return makeResult(for: request)
        }
        viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([first, second])

        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(viewModel.rows.map(\.state), [.verified, .skipped])
        XCTAssertEqual(converter.requests.map(\.sourceURL), [first])
    }

    func testStopAfterCurrentSkipsRemainingRows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeFile(named: "First.wav", in: directory)
        let second = try makeFile(named: "Second.wav", in: directory)
        let third = try makeFile(named: "Third.wav", in: directory)
        var viewModel: AudioConverterViewModel!
        let converter = RecordingViewModelConverter { request in
            if request.sourceURL == first {
                await MainActor.run {
                    XCTAssertTrue(viewModel.canRequestStopAfterCurrent)
                    viewModel.requestStopAfterCurrent()
                    XCTAssertFalse(viewModel.canRequestStopAfterCurrent)
                }
            }
            let result = makeResult(for: request)
            try Data("verified-wav-fixture".utf8).write(to: result.outputURL)
            return result
        }
        viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([first, second, third])

        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(viewModel.rows.map(\.state), [.verified, .skipped, .skipped])
        XCTAssertEqual(viewModel.rows.map(\.statusText), [
            AudioConverterCopy.verified,
            AudioConverterCopy.skipped,
            AudioConverterCopy.skipped
        ])
        XCTAssertEqual(converter.requests.map(\.sourceURL), [first])
        let verifiedURL = try XCTUnwrap(viewModel.rows[0].outputURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: verifiedURL.path),
            "Verified WAV must remain after stop-after-current"
        )
        XCTAssertFalse(viewModel.canRequestStopAfterCurrent)
    }

    func testStopAfterThisFileHonestyCopy() throws {
        XCTAssertEqual(AudioConverterCopy.stopAfterThisFile, "Stop After This File")
        XCTAssertEqual(
            AudioConverterCopy.stopAfterThisFileHelp,
            "Finishes the file that is converting, then skips the rest. Verified WAV files are kept."
        )

        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("label: AudioConverterCopy.stopAfterThisFile")
                || source.contains("label: \"Stop After This File\""),
            "Visible Stop control must be labeled Stop After This File"
        )
        XCTAssertTrue(
            source.contains("help: AudioConverterCopy.stopAfterThisFileHelp")
                || source.contains("Finishes the file that is converting, then skips the rest. Verified WAV files are kept."),
            "Stop help must explain skip-rest and kept WAVs"
        )
        XCTAssertTrue(source.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertFalse(
            source.contains("label: \"Stop\""),
            "Visible converting control must not keep the short Stop label"
        )
    }

    func testStartConversionSetsBusySynchronouslyAndRejectsDuplicateStarts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let converter = RecordingViewModelConverter { request in
            try? await Task.sleep(for: .milliseconds(80))
            return makeResult(for: request)
        }
        let viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([source])

        viewModel.startConversion()

        XCTAssertTrue(viewModel.isConverting)
        viewModel.startConversion()
        try await waitUntil { converter.requests.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(converter.requests.count, 1)
        try await waitUntil { !viewModel.isConverting }
    }

    func testInboxAddFailureLeavesRowVerifiedWithWarning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let converter = RecordingViewModelConverter { request in
            makeResult(for: request)
        }
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            outputInboxStore: ThrowingFixtureOutputInboxStore()
        )
        viewModel.addFileURLs([source])

        _ = await viewModel.convertQueuedRows()

        let row = try XCTUnwrap(viewModel.rows.first)
        XCTAssertEqual(row.state, .verified)
        XCTAssertEqual(row.statusText, AudioConverterCopy.verifiedWithHandoffWarning)
        XCTAssertEqual(viewModel.statusText, AudioConverterCopy.verifiedWithHandoffWarning)
        XCTAssertNotNil(row.outputURL)
    }

    func testEditingWAVPresetPersistsAndUpdatesPresetSummary() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let viewModel = makeViewModel(outputFolder: directory, settingsStore: settingsStore)

        XCTAssertEqual(viewModel.currentAudioPreset, .cubaseDefault)
        XCTAssertEqual(viewModel.presetSummaryText, "44.1 kHz - 24-bit - Preserve mono/stereo")

        viewModel.updateWAVPreset(sampleRate: 48000, bitDepth: 16, channelMode: .mono)

        XCTAssertEqual(settingsStore.settings.audioPreset.sampleRate, 48000)
        XCTAssertEqual(settingsStore.settings.audioPreset.bitDepth, 16)
        XCTAssertEqual(settingsStore.settings.audioPreset.channelMode, .mono)
        XCTAssertEqual(settingsStore.settings.audioPreset.channelCount, 1)
        XCTAssertEqual(viewModel.currentAudioPreset, settingsStore.settings.audioPreset)
        XCTAssertEqual(viewModel.presetSummaryText, "48 kHz - 16-bit - Mono")

        viewModel.updateWAVPreset(sampleRate: 96000, bitDepth: 24, channelMode: .stereo)

        XCTAssertEqual(settingsStore.settings.audioPreset.channelCount, 2)
        XCTAssertEqual(viewModel.presetSummaryText, "96 kHz - 24-bit - Stereo")
    }

    func testSecondRowPreviewShowsNumericSuffixWhenFileExists() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("existing-wav".utf8).write(
            to: directory.appendingPathComponent("Loop - 44100Hz 24bit.wav", isDirectory: false)
        )
        let source = try makeFile(named: "Loop.m4a", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.addFileURLs([source])

        XCTAssertTrue(
            viewModel.rows.first?.plannedOutputName.contains(" 2") ?? false,
            "Planned name must suffix when the output file already exists, got: \(viewModel.rows.first?.plannedOutputName ?? "nil")"
        )
        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 44100Hz 24bit 2.wav")
    }

    func testEditingWAVPresetRefreshesQueuedOutputNames() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.addFileURLs([source])

        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 44100Hz 24bit.wav")

        viewModel.updateWAVPreset(sampleRate: 48000, bitDepth: 16, channelMode: .mono)

        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 48000Hz 16bit.wav")
    }

    func testConversionUsesEditedWAVPreset() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let converter = RecordingViewModelConverter { request in
            makeResult(for: request)
        }
        let viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([source])

        viewModel.updateWAVPreset(sampleRate: 88200, bitDepth: 32, channelMode: .stereo)
        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(converter.requests.first?.preset.sampleRate, 88200)
        XCTAssertEqual(converter.requests.first?.preset.bitDepth, 32)
        XCTAssertEqual(converter.requests.first?.preset.channelMode, .stereo)
        XCTAssertEqual(converter.requests.first?.preset.channelCount, 2)
    }

    func testExternalPresetChangeUpdatesVisiblePresetAndQueuedNames() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let viewModel = makeViewModel(outputFolder: directory, settingsStore: settingsStore)
        viewModel.addFileURLs([source])
        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 44100Hz 24bit.wav")

        // External writer (e.g. the Settings pane): durable truth changes
        // without going through the view model.
        try settingsStore.updateSettings { settings in
            settings.audioPreset = AudioPreset(
                sampleRate: 48000,
                bitDepth: 16,
                channelCount: 1,
                channelMode: .mono
            )
        }
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(viewModel.currentAudioPreset.sampleRate, 48000)
        XCTAssertEqual(viewModel.currentAudioPreset.bitDepth, 16)
        XCTAssertEqual(viewModel.currentAudioPreset.channelMode, .mono)
        XCTAssertEqual(viewModel.presetSummaryText, "48 kHz - 16-bit - Mono")
        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 48000Hz 16bit.wav")
        // The subscriber mirrors durable truth and never writes a stale view
        // snapshot back over the newer edit.
        XCTAssertEqual(settingsStore.settings.audioPreset.sampleRate, 48000)
    }

    func testConversionAdmitsDurablePresetSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let converter = RecordingViewModelConverter { request in
            makeResult(for: request)
        }
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore
        )
        viewModel.addFileURLs([source])

        // Durable change lands after the initial load and before admission.
        // No queue drain: admission itself must reconcile stale view state.
        try settingsStore.updateSettings { settings in
            settings.audioPreset = AudioPreset(
                sampleRate: 48000,
                bitDepth: 16,
                channelCount: 1,
                channelMode: .mono
            )
        }

        let outcomes = await viewModel.convertQueuedRows()

        XCTAssertEqual(outcomes.count, 1)
        let request = try XCTUnwrap(converter.requests.first)
        XCTAssertEqual(request.preset.sampleRate, 48000)
        XCTAssertEqual(request.preset.bitDepth, 16)
        XCTAssertEqual(request.preset.channelMode, .mono)
        XCTAssertEqual(request.preset.channelCount, 1)
        XCTAssertEqual(viewModel.currentAudioPreset, request.preset)
        XCTAssertEqual(viewModel.rows.first?.state, .verified)
    }

    func testConversionRunKeepsAdmissionSnapshotAcrossMidRunSettingsChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeFile(named: "First.m4a", in: directory)
        let second = try makeFile(named: "Second.m4a", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let admissionPreset = settingsStore.settings.audioPreset
        let converter = RecordingViewModelConverter { request in
            // Durable change lands while the admitted run is in flight.
            try? settingsStore.updateSettings { settings in
                settings.audioPreset = AudioPreset(
                    sampleRate: 96000,
                    bitDepth: 32,
                    channelCount: 2,
                    channelMode: .stereo
                )
            }
            return makeResult(for: request)
        }
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore
        )
        viewModel.addFileURLs([first, second])

        let outcomes = await viewModel.convertQueuedRows()

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(converter.requests.count, 2)
        for request in converter.requests {
            XCTAssertEqual(
                request.preset,
                admissionPreset,
                "Every file in a run must use the admission snapshot, not a mid-run edit"
            )
        }
    }

    func testActiveBatchDefersExternalPresetChangeUntilAfterRun() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeFile(named: "First.m4a", in: directory)
        let second = try makeFile(named: "Second.m4a", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let gate = ConversionBlockGate()
        let converter = RecordingViewModelConverter { request in
            if request.sourceURL == first {
                await gate.signalEntered()
                await gate.waitForRelease()
            }
            return makeResult(for: request)
        }
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore
        )
        viewModel.addFileURLs([first, second])
        let admissionPreset = viewModel.currentAudioPreset
        let admittedSecondName = try XCTUnwrap(
            viewModel.rows.first(where: { $0.sourceURL == second })?.plannedOutputName
        )

        let conversionTask = Task { await viewModel.convertQueuedRows() }
        await gate.waitForEntered()
        XCTAssertTrue(viewModel.isConverting)

        let latestPreset = AudioPreset(
            sampleRate: 96000,
            bitDepth: 32,
            channelCount: 2,
            channelMode: .stereo
        )
        try settingsStore.updateSettings { settings in
            settings.audioPreset = latestPreset
        }
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(
            viewModel.currentAudioPreset,
            admissionPreset,
            "Visible preset must stay admitted while the batch is active"
        )
        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == second })?.plannedOutputName,
            admittedSecondName,
            "Queued names must stay admitted while the batch is active"
        )

        // New rows added while the batch is active belong to the next batch,
        // but their visible names must stay aligned to the admitted snapshot.
        let third = try makeFile(named: "Third.m4a", in: directory)
        viewModel.addFileURLs([third])
        XCTAssertEqual(
            viewModel.currentAudioPreset,
            admissionPreset,
            "Visible preset must stay admitted even when new files are added mid-run"
        )
        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == third })?.state,
            .queued
        )
        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == third })?.plannedOutputName,
            "Third - 44100Hz 24bit.wav",
            "Rows added mid-run must plan names from the admitted snapshot, not the latest durable edit"
        )
        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == second })?.plannedOutputName,
            admittedSecondName,
            "Existing queued names must stay admitted when new files are added mid-run"
        )

        viewModel.updateWAVPreset(sampleRate: 48000, bitDepth: 16, channelMode: .mono)
        XCTAssertEqual(
            viewModel.currentAudioPreset,
            admissionPreset,
            "Programmatic preset edits must not apply while converting"
        )
        XCTAssertEqual(
            settingsStore.settings.audioPreset,
            latestPreset,
            "Programmatic preset edits must not overwrite durable settings while converting"
        )

        await gate.release()
        let outcomes = await conversionTask.value
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(converter.requests.count, 2)
        for request in converter.requests {
            XCTAssertEqual(
                request.preset,
                admissionPreset,
                "Every file in a run must use the admission snapshot, not a mid-run edit"
            )
        }
        XCTAssertEqual(
            viewModel.currentAudioPreset,
            latestPreset,
            "Latest durable preset must appear after the run for the next batch"
        )
        XCTAssertFalse(viewModel.isConverting)

        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == third })?.plannedOutputName,
            "Third - 96000Hz 32bit.wav",
            "Queued row added mid-run belongs to the next batch and must converge to latest durable after the run"
        )

        let followUpOutcomes = await viewModel.convertQueuedRows()
        XCTAssertEqual(followUpOutcomes.count, 1, "Converged queued row must convert in the next batch")
        XCTAssertEqual(converter.requests.count, 3)
        XCTAssertEqual(
            converter.requests.last?.preset,
            latestPreset,
            "Next batch must admit the latest durable preset"
        )
        XCTAssertEqual(
            viewModel.rows.first(where: { $0.sourceURL == third })?.state,
            .verified
        )
    }

    func testOutputGuardFailureFailsRowsWithoutFalseSuccess() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let archiveRoot = directory.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let outputFolder = archiveRoot.appendingPathComponent("Out", isDirectory: true)
        let source = try makeFile(named: "Loop.m4a", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(
                outputFolder: StoredFolderLocation(url: outputFolder),
                archiveRoots: [StoredArchiveRoot(path: archiveRoot.path)]
            )
        )
        let converter = RecordingViewModelConverter { request in
            makeResult(for: request)
        }
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore
        )
        viewModel.addFileURLs([source])

        let outcomes = await viewModel.convertQueuedRows()

        XCTAssertTrue(converter.requests.isEmpty, "Guard failure must not start any conversion")
        XCTAssertTrue(outcomes.isEmpty, "Admission failure returns no outcomes")
        XCTAssertEqual(viewModel.rows.first?.state, .failed)
        XCTAssertFalse(viewModel.isConverting)
        XCTAssertFalse(
            viewModel.rows.contains { $0.state == .verified },
            "A refused output folder must never report success"
        )
        XCTAssertTrue(
            viewModel.statusText.localizedCaseInsensitiveContains("archive"),
            "Admission refusal must explain itself, got: \(viewModel.statusText)"
        )
    }

    func testAudioConverterViewContainsUISpecCopy() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )

        [
            "WAV Converter",
            "Drop audio files to convert",
            "Choose Files",
            "Convert",
            "AudioConverterCopy.stopAfterThisFile",
            "viewModel.presetSummaryText",
            "AudioConverterCopy.ready",
            "Verified WAV ready",
            "Choose FFmpeg",
            "Reveal in Finder"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing copy: \($0)")
        }
    }

    func testAudioConverterViewContainsEditablePresetControls() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )

        [
            "Edit Preset",
            "HubSegmentedChoice(\"Sample rate\"",
            "HubSegmentedChoice(\"Bit depth\"",
            "HubSegmentedChoice(\"Channel handling\"",
            "viewModel.presetSummaryText",
            "updateWAVPreset(sampleRate:"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing preset control source: \($0)")
        }

        XCTAssertFalse(source.contains("Text(\"44.1 kHz - 24-bit - Preserve mono/stereo\")"))
    }

    func testAudioConverterViewExcludesOutOfScopeFeatureCopy() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )
        let forbiddenPattern = "trim|fade|loudness|key analysis|downloader|recording|recursive"

        XCTAssertNil(
            source.range(of: forbiddenPattern, options: [.regularExpression, .caseInsensitive])
        )
    }

    private func makeViewModel(
        outputFolder: URL,
        converter: RecordingViewModelConverter = RecordingViewModelConverter { request in
            makeResult(for: request)
        },
        settingsStore: FixtureSettingsStore? = nil,
        outputInboxStore: any OutputInboxStore = FixtureOutputInboxStore(),
        ffmpegHealthChecker: FFmpegHealthChecker = FFmpegHealthChecker()
    ) -> AudioConverterViewModel {
        let settingsStore = settingsStore ?? FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: outputFolder))
        )
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: settingsStore,
            outputInboxStore: outputInboxStore,
            jobRunner: FixtureJobRunner(),
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
        return AudioConverterViewModel(
            context: context,
            batchUseCase: BatchAudioConversionUseCase(
                settingsStore: context.settingsStore,
                outputInboxStore: context.outputInboxStore,
                converterFactory: { _ in converter }
            ),
            ffmpegHealthChecker: ffmpegHealthChecker
        )
    }

    /// The handoff is delivered on the next main-queue turn (see `bindConverterHandoff`).
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try Data("fixture".utf8).write(to: url)
        return url
    }
}

private func makeResult(for request: ConversionRequest) -> ConversionResult {
    ConversionResult(
        sourceURL: request.sourceURL,
        outputURL: request.outputDirectory
            .appendingPathComponent(request.sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("wav"),
        spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
        converterPath: .native
    )
}

private final class FixtureSettingsStore: SettingsStore, @unchecked Sendable {
    var settings: AppSettings
    private let subject = PassthroughSubject<AppSettings, Never>()

    init(settings: AppSettings) {
        self.settings = settings
    }

    var settingsChanges: AnyPublisher<AppSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        self.settings = settings
        subject.send(settings)
    }

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        update(&settings)
        subject.send(settings)
    }
}

private struct FixtureOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct ThrowingFixtureOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {
        throw FixtureOutputInboxError.forced
    }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private enum FixtureOutputInboxError: LocalizedError {
    case forced

    var errorDescription: String? {
        "forced inbox failure"
    }
}

private struct FixtureJobRunner: JobRunning {
    func listJobs() -> [Job] { [] }
    func job(id: Job.ID) -> Job? { nil }
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        Job(sourceToolID: sourceToolID, title: title)
    }
    func cancelJob(id: Job.ID) {}
}

private struct FixtureFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? { nil }

    @MainActor
    func chooseDirectory(prompt: String) -> URL? { nil }

    @MainActor
    func chooseExecutable(prompt: String) -> URL? { nil }

    @MainActor
    func chooseAudioFile(prompt: String) -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct FixtureDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

private struct FakeExternalProcessRunner: ExternalProcessRunning {
    var result: Result<ExternalProcessResult, Error>

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try result.get()
    }
}

private final class RecordingViewModelConverter: AudioConverting, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (ConversionRequest) async throws -> ConversionResult
    private var storedRequests: [ConversionRequest] = []

    var requests: [ConversionRequest] {
        lock.withLock { storedRequests }
    }

    init(handler: @escaping @Sendable (ConversionRequest) async throws -> ConversionResult) {
        self.handler = handler
    }

    func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        lock.withLock {
            storedRequests.append(request)
        }
        return try await handler(request)
    }
}

private final class EmissionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func increment() {
        lock.withLock { storedCount += 1 }
    }
}

/// Deterministic mid-batch gate: the converter signals entry, then suspends
/// until the test releases it. No sleeps; both sides rendezvous on
/// continuations.
private actor ConversionBlockGate {
    private var didEnter = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func signalEntered() {
        didEnter = true
        enteredContinuation?.resume(returning: ())
        enteredContinuation = nil
    }

    func waitForEntered() async {
        if didEnter { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func waitForRelease() async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume(returning: ())
        releaseContinuation = nil
    }
}

private func waitUntil(
    timeoutAttempts: Int = 50,
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<timeoutAttempts {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for condition")
}
