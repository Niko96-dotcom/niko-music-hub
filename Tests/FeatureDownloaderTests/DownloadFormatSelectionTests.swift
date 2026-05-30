@testable import FeatureDownloader
import XCTest

final class DownloadFormatSelectionTests: XCTestCase {
    func testAudioMP3UsesExtractAudioFlags() {
        let args = YtDlpFormatArgumentBuilder.arguments(
            for: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .mp3)
        )
        XCTAssertEqual(args.formatSelector, "bestaudio/best")
        XCTAssertEqual(args.extraArguments, ["--extract-audio", "--audio-format", "mp3"])
    }

    func testAudioBestDoesNotTranscode() {
        let args = YtDlpFormatArgumentBuilder.arguments(
            for: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .best)
        )
        XCTAssertEqual(args.formatSelector, "bestaudio/best")
        XCTAssertTrue(args.extraArguments.isEmpty)
    }

    func testVideo360MatchesPreviousDefault() {
        let args = YtDlpFormatArgumentBuilder.arguments(
            for: DownloadFormatSelection(mediaKind: .videoWithAudio, videoQuality: .mp4_360)
        )
        XCTAssertEqual(
            args.formatSelector,
            "best[height<=360][ext=mp4]/best[height<=360]/worst"
        )
    }

    func testVideo720Selector() {
        let args = YtDlpFormatArgumentBuilder.arguments(
            for: DownloadFormatSelection(mediaKind: .videoWithAudio, videoQuality: .mp4_720)
        )
        XCTAssertEqual(
            args.formatSelector,
            "best[height<=720][ext=mp4]/best[height<=720]/best"
        )
    }

    func testSummaryLabelReflectsSelection() {
        let selection = DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .m4a)
        XCTAssertEqual(selection.summaryLabel, "Audio — M4A")
    }
}
