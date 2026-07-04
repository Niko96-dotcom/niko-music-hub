import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ConverterHandoffTests: XCTestCase {
    func testArchiveViewModelRoutesConverterHandoff() {
        let router = QuickAccessRouter()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.requestConverterHandoff = { url in
            router.openConverter(with: [url])
        }

        let preview = URL(fileURLWithPath: "/tmp/preview.wav")
        let candidate = PreviewCandidate(
            filePath: preview,
            fileName: "preview.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix,
            fileExtension: "wav"
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Song", isDirectory: true),
            originalFolderName: "Song",
            displayTitle: "Song",
            previewCandidates: [candidate],
            mainPreviewCandidateID: candidate.id
        )

        viewModel.convertMainPreview(for: song)
        XCTAssertEqual(router.selectedToolID, ToolFeatureID("wav-converter"))
        XCTAssertEqual(router.prefilledConverterURLs, [preview])
    }
}
