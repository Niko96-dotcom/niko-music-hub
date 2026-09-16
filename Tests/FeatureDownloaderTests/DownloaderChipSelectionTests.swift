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
        XCTAssertTrue(
            source.contains("HubChoiceChips("),
            "Playlist and media-kind chips must use HubChoiceChips so .isSelected is exposed"
        )
        XCTAssertFalse(
            source.contains("struct DownloaderTextChip"),
            "One-off DownloaderTextChip must be removed in favor of HubChoiceChips"
        )
    }
}
