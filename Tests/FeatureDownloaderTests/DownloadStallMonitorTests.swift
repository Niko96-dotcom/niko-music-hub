@testable import FeatureDownloader
import XCTest

final class DownloadStallMonitorTests: XCTestCase {
    func testStallsAfter120SecondsWithoutActivity() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 119)
        XCTAssertFalse(monitor.checkStalled())
        clock.advance(by: 1)
        XCTAssertTrue(monitor.checkStalled())
    }

    func testActivityResetsStallWindow() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 119)
        monitor.recordActivity()
        clock.advance(by: 119)
        XCTAssertFalse(monitor.checkStalled())
    }

    func testStallErrorMessage() {
        XCTAssertEqual(
            DownloadStallMonitor.stallErrorMessage,
            "Download stalled — no progress for 2 minutes"
        )
    }

    func testSlowHintAfter30Seconds() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 29)
        XCTAssertFalse(monitor.checkSlowHint())
        XCTAssertFalse(monitor.checkStalled())
        clock.advance(by: 1)
        XCTAssertTrue(monitor.checkSlowHint())
        XCTAssertFalse(monitor.checkStalled())
        clock.advance(by: 90)
        XCTAssertTrue(monitor.checkSlowHint())
        XCTAssertTrue(monitor.checkStalled())
        XCTAssertEqual(
            DownloadStallMonitor.slowHintMessage,
            "Still working. This download has not reported new data."
        )
        XCTAssertEqual(DownloadStallMonitor.slowHintSeconds, 30)
    }

    func testFakeClockAdvancesWithoutSleep() {
        let clock = FakeDownloadStallClock(start: Date())
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        for _ in 0..<5 {
            clock.advance(by: 30)
        }
        XCTAssertTrue(monitor.checkStalled())
    }

    func testPostProcessingSilenceUsesThirtyMinuteCeilingAndHidesSlowHint() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity(line: "NIKO_PROGRESS:{'status': 'finished'}")
        monitor.recordActivity(line: "NIKO_POSTPROCESS:started:ExtractAudio")
        XCTAssertEqual(monitor.phase, .postProcessing(step: "ExtractAudio"))

        clock.advance(by: 29 * 60 + 59)
        XCTAssertFalse(monitor.checkStalled())
        XCTAssertFalse(monitor.checkSlowHint())
        XCTAssertNil(monitor.stallFailureMessage())

        clock.advance(by: 1)
        XCTAssertTrue(monitor.checkStalled())
        XCTAssertEqual(monitor.stallFailureMessage(), DownloadStallMonitor.postProcessingStallErrorMessage)
        XCTAssertEqual(
            DownloadStallMonitor.postProcessingStallErrorMessage,
            "Conversion stalled — no progress for 30 minutes"
        )
    }

    func testDownloadLineReArmsTwoMinuteRuleAfterPostProcessing() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity(line: "[ExtractAudio] Destination: /tmp/a.wav")
        clock.advance(by: 600)
        XCTAssertFalse(monitor.checkStalled())

        monitor.recordActivity(line: "[download] Downloading item 2 of 3")
        XCTAssertEqual(monitor.phase, .downloading)
        clock.advance(by: 120)
        XCTAssertEqual(monitor.stallFailureMessage(), DownloadStallMonitor.stallErrorMessage)
    }

    func testLinesWithoutPhaseKeepTheCurrentPhase() {
        let monitor = DownloadStallMonitor(clock: FakeDownloadStallClock(start: Date()))
        monitor.recordActivity(line: "NIKO_POSTPROCESS:started:Merger")
        monitor.recordActivity(line: "WARNING: something harmless")
        monitor.recordActivity(line: "Deleting original file a.webm (pass -k to keep)")
        monitor.recordActivity(line: "NIKO_POSTPROCESS:finished:Merger")
        XCTAssertEqual(monitor.phase, .postProcessing(step: "Merger"))
    }

    func testPhaseClassificationOfYtDlpLines() {
        let cases: [(String, DownloadActivityPhase?)] = [
            ("NIKO_PROGRESS:{'status': 'downloading'}", .downloading),
            ("[download]  42.0% of 3.00MiB", .downloading),
            ("NIKO_MUSIC_HUB_FILE:/tmp/out.wav", .downloading),
            ("NIKO_POSTPROCESS:started:ExtractAudio", .postProcessing(step: "ExtractAudio")),
            ("NIKO_POSTPROCESS:finished:FixupM4a", .postProcessing(step: "FixupM4a")),
            ("[ExtractAudio] Destination: /tmp/out.mp3", .postProcessing(step: "ExtractAudio")),
            ("[Merger] Merging formats into \"/tmp/out.mp4\"", .postProcessing(step: "Merger")),
            ("[FixupM4a] Correcting container of \"/tmp/out.m4a\"", .postProcessing(step: "FixupM4a")),
            ("[Metadata] Adding metadata to \"/tmp/out.mp3\"", .postProcessing(step: "Metadata")),
            ("[EmbedThumbnail] ffmpeg: Adding thumbnail", .postProcessing(step: "EmbedThumbnail")),
            ("[youtube] abc: Downloading webpage", nil),
            ("[info] abc: Downloading 1 format(s): 251", nil),
            ("WARNING: unable to extract", nil),
        ]
        for (line, expected) in cases {
            XCTAssertEqual(DownloadActivityPhase.announced(by: line), expected, line)
        }
        XCTAssertEqual(
            DownloadActivityPhase.latest(in: ["NIKO_PROGRESS:x", "NIKO_POSTPROCESS:started:ExtractAudio", "WARNING: y"]),
            .postProcessing(step: "ExtractAudio")
        )
        XCTAssertNil(DownloadActivityPhase.latest(in: ["Retry 2/3 in 2s..."]))
    }

    func testPostProcessingStatusCopy() {
        XCTAssertNil(DownloadActivityPhase.downloading.statusMessage)
        XCTAssertEqual(DownloadActivityPhase.postProcessing(step: "ExtractAudio").statusMessage, "Converting audio…")
        XCTAssertEqual(DownloadActivityPhase.postProcessing(step: "Merger").statusMessage, "Merging audio and video…")
        XCTAssertEqual(DownloadActivityPhase.postProcessing(step: "VideoConvertor").statusMessage, "Converting video…")
        XCTAssertEqual(DownloadActivityPhase.postProcessing(step: "FixupM4a").statusMessage, "Finishing file…")
    }

    func testDownloadArgumentsReportPostProcessingInQuietMode() {
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        let arguments = YtDlpDownloadCommandBuilder.downloadArguments(for: request)
        XCTAssertTrue(arguments.contains("--print"), "--print implies quiet mode")
        let templates = arguments.indices.dropLast()
            .filter { arguments[$0] == "--progress-template" }
            .map { arguments[$0 + 1] }
        XCTAssertEqual(templates, [
            "NIKO_PROGRESS:%(progress)s",
            "postprocess:NIKO_POSTPROCESS:%(progress.status)s:%(progress.postprocessor)s",
        ])
    }
}
