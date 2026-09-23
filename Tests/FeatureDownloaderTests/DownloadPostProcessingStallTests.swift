import AppCore
@testable import FeatureDownloader
import XCTest

/// yt-dlp goes quiet while ffmpeg post-processes a finished download
/// (`--extract-audio`, merging, fixups). That silence must not trip the
/// 120 s download-stall rule, while a real download stall still must.
final class DownloadPostProcessingStallTests: XCTestCase {
    private let downloadedLines = [
        "NIKO_PROGRESS:{'status': 'downloading', '_percent_str': ' 50.0%'}\n",
        "NIKO_PROGRESS:{'status': 'downloading', '_percent_str': '100.0%'}\n",
        "NIKO_PROGRESS:{'status': 'finished', '_percent_str': '100.0%'}\n",
    ]

    func testSilentExtractAudioAfterFullDownloadIsNotKilledAsStalled() async throws {
        let outputURL = temporaryOutputURL(ext: "wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        await assertCompletes(script: downloadedLines.map(ScriptStep.emit) + [
            .emit("[ExtractAudio] Destination: \(outputURL.path)\n"),
            .advanceClock(180),
            .pause,
            .finish(outputURL),
        ], output: outputURL)
    }

    func testSilentPostProcessorReportedThroughProgressTemplateIsNotKilledAsStalled() async throws {
        let outputURL = temporaryOutputURL(ext: "mp3")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        await assertCompletes(script: downloadedLines.map(ScriptStep.emit) + [
            .emit("NIKO_POSTPROCESS:started:ExtractAudio\n"),
            .advanceClock(20 * 60),
            .pause,
            .emit("NIKO_POSTPROCESS:finished:ExtractAudio\n"),
            .finish(outputURL),
        ], output: outputURL)
    }

    func testSilentDownloadPhaseStillStallsAfterTwoMinutes() async throws {
        try await assertStalls(
            script: [
                .emit("NIKO_PROGRESS:{'status': 'downloading', '_percent_str': ' 42.0%'}\n"),
                .advanceClock(121),
                .hang,
            ],
            message: "Download stalled — no progress for 2 minutes"
        )
    }

    func testNextPlaylistItemReArmsTheDownloadStallRule() async throws {
        try await assertStalls(
            script: downloadedLines.map(ScriptStep.emit) + [
                .emit("NIKO_POSTPROCESS:started:ExtractAudio\n"),
                .advanceClock(10 * 60),
                .pause,
                .emit("NIKO_POSTPROCESS:finished:ExtractAudio\n"),
                .emit("NIKO_MUSIC_HUB_FILE:/tmp/item-1.wav\n"),
                .emit("NIKO_PROGRESS:{'status': 'downloading', '_percent_str': '  3.0%'}\n"),
                .advanceClock(121),
                .hang,
            ],
            message: "Download stalled — no progress for 2 minutes"
        )
    }

    func testHungPostProcessingEndsAtTheThirtyMinuteCeiling() async throws {
        try await assertStalls(
            script: downloadedLines.map(ScriptStep.emit) + [
                .emit("NIKO_POSTPROCESS:started:ExtractAudio\n"),
                .advanceClock(29 * 60),
                .pause,
                .advanceClock(61),
                .hang,
            ],
            message: "Conversion stalled — no progress for 30 minutes"
        )
    }

    // MARK: - Helpers

    private func temporaryOutputURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("post-processing-\(UUID().uuidString).\(ext)")
    }

    private func assertCompletes(
        script: [ScriptStep],
        output outputURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let result = try await download(script: script)
            XCTAssertEqual(result.outputURLs, [outputURL], file: file, line: line)
        } catch {
            XCTFail("Expected the download to finish, got \(error)", file: file, line: line)
        }
    }

    private func download(script: [ScriptStep]) async throws -> DownloadResult {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let downloader = YtDlpDownloader(
            runner: ScriptedStreamingRunner(script: script, clock: clock),
            stallClock: clock,
            stallCheckIntervalNanoseconds: 5_000_000
        )
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com/long-mix")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        return try await downloader.download(request) { _ in }
    }

    private func assertStalls(
        script: [ScriptStep],
        message expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await download(script: script)
            XCTFail("Expected a stall failure", file: file, line: line)
        } catch let DownloadError.downloadFailed(message) {
            XCTAssertEqual(message, expected, file: file, line: line)
        }
    }
}

private enum ScriptStep: Sendable {
    case emit(String)
    case advanceClock(TimeInterval)
    /// Real time for the stall poller to observe the advanced clock.
    case pause
    case finish(URL)
    /// Stays silent until the downloader cancels the process.
    case hang
}

private final class ScriptedStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    let script: [ScriptStep]
    let clock: FakeDownloadStallClock

    init(script: [ScriptStep], clock: FakeDownloadStallClock) {
        self.script = script
        self.clock = clock
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        for step in script {
            switch step {
            case let .emit(text):
                onStandardOutput(text)
            case let .advanceClock(seconds):
                clock.advance(by: seconds)
            case .pause:
                try await Task.sleep(nanoseconds: 200_000_000)
            case let .finish(outputURL):
                FileManager.default.createFile(atPath: outputURL.path, contents: Data("audio".utf8))
                onStandardOutput("NIKO_MUSIC_HUB_FILE:\(outputURL.path)\n")
            case .hang:
                while true {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}
