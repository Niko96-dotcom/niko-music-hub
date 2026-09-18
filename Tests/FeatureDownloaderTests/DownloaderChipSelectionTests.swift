@testable import FeatureDownloader
import XCTest

final class DownloaderChipSelectionTests: XCTestCase {
    func testMediaKindLabelsMatchVisibleCopy() {
        XCTAssertEqual(DownloadMediaKind.audioOnly.label, "Audio only")
        XCTAssertEqual(DownloadMediaKind.videoWithAudio.label, "Video + audio")
    }

    func testDownloaderChipsUseHubChoiceChips() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureDownloader/DownloaderView.swift",
            encoding: .utf8
        )
        // Two-option settings use the shared HubSegmentedChoice (exposes .isSelected
        // per segment); three-or-more still use HubChoiceChips.
        XCTAssertTrue(
            source.contains("HubSegmentedChoice("),
            "Playlist and media-kind selectors must use HubSegmentedChoice so .isSelected is exposed"
        )
        XCTAssertFalse(
            source.contains("struct DownloaderTextChip"),
            "One-off DownloaderTextChip must be removed in favor of HubChoiceChips"
        )
    }
}
