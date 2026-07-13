import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveSongAnalysisCoordinatorTests: XCTestCase {
    func testCancelPropagatesIntoStructuredEstimatorAndPreventsApply() async throws {
        let probe = CancelableEstimatorProbe()
        let coordinator = ArchiveMixdownAnalysisCoordinator(
            bpmEstimator: { _ in await probe.run() },
            keyEstimator: { _ in MixdownKeyEstimate(key: "C major", confidence: "test") }
        )
        let previewURL = URL(fileURLWithPath: "/tmp/cancelable-analysis.wav")
        let preview = PreviewCandidate(
            filePath: previewURL,
            fileName: previewURL.lastPathComponent,
            folderRole: .mixdown,
            modifiedAt: Date(),
            detectedRole: .mainMix
        )
        var song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/cancelable-song"),
            originalFolderName: "Cancelable",
            displayTitle: "Cancelable",
            previewCandidates: [preview]
        )
        song.mainPreviewCandidateID = preview.id
        let cacheKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: song))
        let keyCache = [cacheKey: MixdownKeyEstimate(key: "C major", confidence: "cached")]
        var didApply = false

        coordinator.refresh(
            for: song,
            bpmCache: [:],
            keyCache: keyCache,
            isStillSelected: { _, _ in true },
            apply: { _, _, _ in didApply = true }
        )
        try await waitUntil { await probe.started }
        coordinator.cancel()
        try await waitUntil { await probe.canceled }

        XCTAssertFalse(didApply)
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for analysis state", file: file, line: line)
        throw AnalysisTestError.timeout
    }
}

private actor CancelableEstimatorProbe {
    private(set) var started = false
    private(set) var canceled = false

    func run() async -> MixdownBPMEstimate? {
        started = true
        do {
            try await Task.sleep(for: .seconds(10))
            return MixdownBPMEstimate(bpm: 120, confidence: "test")
        } catch is CancellationError {
            canceled = true
            return nil
        } catch {
            return nil
        }
    }
}

private enum AnalysisTestError: Error {
    case timeout
}
