import XCTest
@testable import NikoMusicCore

final class PreviewRankingTiebreakTests: XCTestCase {
    private let ranker = PreviewConfidenceRanker()
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testDecidingFactorIsScoreWhenConfidenceDiffers() {
        let high = scoredCandidate(name: "A.wav", score: 120)
        let low = scoredCandidate(name: "B.wav", score: 90)
        XCTAssertEqual(ranker.decidingFactor(winner: high, runnerUp: low), .score)
        XCTAssertNil(PreviewRankingExplainability.tiebreakCallout(winner: high, runnerUp: low))
    }

    func testDecidingFactorIsVersionWhenScoresEqual() {
        let v3 = scoredCandidate(
            name: "Song v3.wav",
            score: 100,
            version: 3,
            ext: "wav",
            duration: 180
        )
        let v2 = scoredCandidate(
            name: "Song v2.wav",
            score: 100,
            version: 2,
            ext: "wav",
            duration: 180
        )
        XCTAssertEqual(ranker.decidingFactor(winner: v3, runnerUp: v2), .version)
        let callout = PreviewRankingExplainability.tiebreakCallout(winner: v3, runnerUp: v2)
        XCTAssertEqual(callout, "Equal score — version v3 beat v2")
    }

    func testDecidingFactorIsExtensionWhenScoresEqual() {
        let wav = scoredCandidate(name: "Song.wav", score: 100, ext: "wav", duration: 180)
        let mp3 = scoredCandidate(name: "Song.mp3", score: 100, ext: "mp3", duration: 180)
        XCTAssertEqual(ranker.decidingFactor(winner: wav, runnerUp: mp3), .extensionFormat)
        let callout = PreviewRankingExplainability.tiebreakCallout(winner: wav, runnerUp: mp3)
        XCTAssertEqual(callout, "Equal score — preferred wav over mp3")
    }

    func testDecidingFactorIsDurationWhenScoresEqual() {
        let longer = scoredCandidate(name: "Song long.wav", score: 100, duration: 200)
        let shorter = scoredCandidate(name: "Song short.wav", score: 100, duration: 180)
        XCTAssertEqual(ranker.decidingFactor(winner: longer, runnerUp: shorter), .duration)
        let callout = PreviewRankingExplainability.tiebreakCallout(winner: longer, runnerUp: shorter)
        XCTAssertEqual(callout, "Equal score — longer preview (3:20) beat 3:00")
    }

    func testMainPreviewSummaryIncludesTiebreakCalloutForEqualScoreDurationPick() {
        let longer = candidate(name: "Song long.wav", duration: 200)
        let shorter = candidate(name: "Song short.wav", duration: 180)
        let ranked = ranker.rank([shorter, longer])
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/fixture/Tiebreak Lab"),
            originalFolderName: "Tiebreak Lab",
            displayTitle: "Tiebreak Lab",
            previewCandidates: ranked,
            mainPreviewCandidateID: ranked.first?.id
        )
        let summary = PreviewRankingExplainability.mainPreviewSummary(for: song)
        XCTAssertTrue(summary?.contains("Equal score — longer preview") == true)
    }

    func testSelectedSongHeaderIncludesTiebreakCallout() {
        let longer = candidate(name: "Song long.wav", duration: 200)
        let shorter = candidate(name: "Song short.wav", duration: 180)
        let ranked = ranker.rank([shorter, longer])
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/fixture/Tiebreak Lab"),
            originalFolderName: "Tiebreak Lab",
            displayTitle: "Tiebreak Lab",
            previewCandidates: ranked,
            mainPreviewCandidateID: ranked.first?.id
        )
        let header = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: song)
        XCTAssertTrue(header?.contains("Equal score — longer preview") == true)
    }

    func testSelectedSongHeaderDoesNotDuplicateTiebreakCallout() {
        let longer = candidate(name: "Song long.wav", duration: 200)
        let shorter = candidate(name: "Song short.wav", duration: 180)
        let ranked = ranker.rank([shorter, longer])
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/fixture/Tiebreak Lab"),
            originalFolderName: "Tiebreak Lab",
            displayTitle: "Tiebreak Lab",
            previewCandidates: ranked,
            mainPreviewCandidateID: ranked.first?.id
        )
        guard let header = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: song) else {
            return XCTFail("expected selected song header")
        }
        let needle = "Equal score — longer preview"
        XCTAssertEqual(header.components(separatedBy: needle).count - 1, 1)
    }

    func testSelectedSongPreviewTiebreakCalloutMatchesExplainability() {
        let longer = candidate(name: "Song long.wav", duration: 200)
        let shorter = candidate(name: "Song short.wav", duration: 180)
        let ranked = ranker.rank([shorter, longer])
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/fixture/Tiebreak Lab"),
            originalFolderName: "Tiebreak Lab",
            displayTitle: "Tiebreak Lab",
            previewCandidates: ranked,
            mainPreviewCandidateID: ranked.first?.id
        )
        XCTAssertEqual(
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: song),
            PreviewRankingExplainability.tiebreakCallout(for: song)
        )
    }

    // MARK: - Helpers

    private func candidate(name: String, duration: Double) -> PreviewCandidate {
        PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/fixture/Mixdown/\(name)"),
            fileName: name,
            folderRole: .mixdown,
            modifiedAt: baseDate,
            detectedRole: .mainMix,
            fileExtension: "wav",
            detectedVersionNumber: nil,
            durationSeconds: duration
        )
    }

    private func scoredCandidate(
        name: String,
        score: Double,
        version: Int? = nil,
        ext: String = "wav",
        duration: Double? = 180
    ) -> PreviewCandidate {
        var candidate = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/fixture/Mixdown/\(name)"),
            fileName: name,
            folderRole: .mixdown,
            modifiedAt: baseDate,
            detectedRole: .mainMix,
            fileExtension: ext,
            detectedVersionNumber: version,
            durationSeconds: duration
        )
        candidate.confidenceScore = score
        return candidate
    }
}
