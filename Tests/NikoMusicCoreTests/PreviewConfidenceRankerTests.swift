import XCTest
@testable import NikoMusicCore

final class PreviewConfidenceRankerTests: XCTestCase {
    private let ranker = PreviewConfidenceRanker()
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixture integration

    func testNeonHookPrefersFullMixOverInstrumental() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        let main = try XCTUnwrap(neon.previewCandidates.first)
        XCTAssertFalse(main.fileName.lowercased().contains("instr"))
        XCTAssertTrue(main.fileName.contains("v3") || main.fileName.lowercased().contains("mix"))
        XCTAssertTrue(main.confidenceReasons.contains(where: { $0.hasPrefix("version:") }))
    }

    func testSecondSongPrefersMixdownOverInstr() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let second = try XCTUnwrap(result.songs.first { $0.displayTitle == "Second Song" })
        let main = try XCTUnwrap(second.previewCandidates.first)
        XCTAssertTrue(main.fileName.lowercased().contains("mixdown"))
    }

    func testPreviewRankingLabFixtureScenarios() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        let main = try XCTUnwrap(lab.previewCandidates.first)

        XCTAssertEqual(main.fileName, "Lab Song v3 mix.wav")
        XCTAssertTrue(main.confidenceReasons.contains("extension:wav"))
        XCTAssertTrue(main.confidenceReasons.contains(where: { $0 == "version:v3" }))
        XCTAssertFalse(main.confidenceReasons.contains(where: { $0.contains("duration:too-short") }))
    }

    func testVersionAndExtensionDoNotAffectConfidenceScore() {
        let v2 = candidate(
            name: "Song v2 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 200
        )
        let v3 = candidate(
            name: "Song v3 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 3,
            ext: "wav",
            duration: 200
        )
        let mp3 = candidate(
            name: "Song mix.mp3",
            role: .mainMix,
            modifiedAt: baseDate,
            version: nil,
            ext: "mp3",
            duration: 200
        )
        let wav = candidate(
            name: "Song mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: nil,
            ext: "wav",
            duration: 200
        )

        let rankedVersions = ranker.rank([v2, v3])
        XCTAssertEqual(rankedVersions[0].confidenceScore, rankedVersions[1].confidenceScore)

        let rankedExtensions = ranker.rank([mp3, wav])
        XCTAssertEqual(rankedExtensions[0].confidenceScore, rankedExtensions[1].confidenceScore)
    }

    func testEqualScoreVersionTiebreakLabFixtureUsesVersionTiebreakCallout() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Version Tiebreak" })
        let main = try XCTUnwrap(lab.previewCandidates.first)
        let runnerUp = try XCTUnwrap(lab.previewCandidates.dropFirst().first)

        XCTAssertEqual(main.fileName, "Tie Song v3 mix.wav")
        XCTAssertEqual(main.confidenceScore, runnerUp.confidenceScore)
        XCTAssertEqual(ranker.decidingFactor(winner: main, runnerUp: runnerUp), .version)
        let callout = try XCTUnwrap(PreviewRankingExplainability.tiebreakCallout(for: lab))
        XCTAssertTrue(callout.contains("Equal score — version v3 beat v2"))
    }

    func testEqualScoreExtensionTiebreakLabFixtureUsesExtensionTiebreakCallout() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Extension Tiebreak" })
        let main = try XCTUnwrap(lab.previewCandidates.first)
        let runnerUp = try XCTUnwrap(lab.previewCandidates.dropFirst().first)

        XCTAssertEqual(main.fileName, "Tie Song mix.flac")
        XCTAssertEqual(main.confidenceScore, runnerUp.confidenceScore)
        XCTAssertEqual(ranker.decidingFactor(winner: main, runnerUp: runnerUp), .extensionFormat)
        let callout = try XCTUnwrap(PreviewRankingExplainability.tiebreakCallout(for: lab))
        XCTAssertTrue(callout.contains("Equal score — preferred flac over mp3"))
    }

    func testEqualScoreTiebreakLabFixtureUsesDurationTiebreakCallout() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Duration Tiebreak" })
        let main = try XCTUnwrap(lab.previewCandidates.first)
        let runnerUp = try XCTUnwrap(lab.previewCandidates.dropFirst().first)

        XCTAssertEqual(main.fileName, "Tie Song mix long.wav")
        XCTAssertEqual(main.confidenceScore, runnerUp.confidenceScore)
        XCTAssertEqual(ranker.decidingFactor(winner: main, runnerUp: runnerUp), .duration)
        let callout = try XCTUnwrap(PreviewRankingExplainability.tiebreakCallout(for: lab))
        XCTAssertTrue(callout.contains("Equal score — longer preview"))
    }

    // MARK: - Unit ranking scenarios

    func testPrefersHigherParsedVersionOverNewerWorseRole() {
        let olderFull = candidate(
            name: "Track v2 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 200
        )
        let newerInstr = candidate(
            name: "Track v5 instr.wav",
            role: .instrumental,
            modifiedAt: baseDate.addingTimeInterval(3600),
            version: 5,
            ext: "wav",
            duration: 200
        )

        let ranked = ranker.rank([newerInstr, olderFull])
        XCTAssertEqual(ranked.first?.fileName, "Track v2 mix.wav")
        XCTAssertTrue(ranked.first?.confidenceReasons.contains("role:full-mix") == true)
    }

    func testVersionTiebreakWhenRoleAndFolderMatch() {
        let v2 = candidate(
            name: "Song v2.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 180
        )
        let v3 = candidate(
            name: "Song v3.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 3,
            ext: "wav",
            duration: 180
        )

        let ranked = ranker.rank([v2, v3])
        XCTAssertEqual(ranked.first?.fileName, "Song v3.wav")
        XCTAssertTrue(ranked.first?.confidenceReasons.contains("version:v3") == true)
    }

    func testMultiDigitVersionBeatsLowerVersionWhenRoleAndFolderMatch() {
        let v2 = candidate(
            name: "Song v2 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 200
        )
        let v10 = candidate(
            name: "Song v10 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 10,
            ext: "wav",
            duration: 200
        )

        let ranked = ranker.rank([v2, v10])
        XCTAssertEqual(ranked.first?.fileName, "Song v10 mix.wav")
        XCTAssertEqual(ranked.first?.detectedVersionNumber, 10)
    }

    func testPrefersWavOverMp3WhenScoresOtherwiseClose() {
        let wav = candidate(
            name: "Song mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: nil,
            ext: "wav",
            duration: 180
        )
        let mp3 = candidate(
            name: "Song mix.mp3",
            role: .mainMix,
            modifiedAt: baseDate,
            version: nil,
            ext: "mp3",
            duration: 180
        )

        let ranked = ranker.rank([mp3, wav])
        XCTAssertEqual(ranked.first?.fileName, "Song mix.wav")
        XCTAssertTrue(ranked.first?.confidenceReasons.contains("extension:wav") == true)
    }

    func testPenalizesVeryShortDuration() {
        let short = candidate(
            name: "Song mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 3,
            ext: "wav",
            duration: 5
        )
        let long = candidate(
            name: "Song mix alt.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 200
        )

        let ranked = ranker.rank([short, long])
        XCTAssertEqual(ranked.first?.fileName, "Song mix alt.wav")
        let scoredShort = ranked.first { $0.fileName == "Song mix.wav" }
        let scoredLong = ranked.first { $0.fileName == "Song mix alt.wav" }
        XCTAssertTrue(scoredShort?.confidenceReasons.contains("duration:too-short") == true)
        XCTAssertTrue(scoredLong?.confidenceReasons.contains("duration:plausible") == true)
    }

    func testInstrumentalLosesToFullMixDespiteHigherVersion() {
        let instr = candidate(
            name: "Song v9 instr.wav",
            role: .instrumental,
            modifiedAt: baseDate.addingTimeInterval(10),
            version: 9,
            ext: "wav",
            duration: 200
        )
        let full = candidate(
            name: "Song v1 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 1,
            ext: "wav",
            duration: 200
        )

        let ranked = ranker.rank([instr, full])
        XCTAssertEqual(ranked.first?.fileName, "Song v1 mix.wav")
    }

    func testCPRAnchorDemotesDemoV06BelowCubaseStyleV4MP3() {
        let context = PreviewRankingProjectContext(anchorCPRVersion: 4, titleTokens: ["90s", "icon"])
        let demo = candidate(
            name: "demo v0.6.mp3",
            role: .unknown,
            modifiedAt: baseDate.addingTimeInterval(100),
            version: nil,
            ext: "mp3",
            duration: 200
        )
        let cubaseMix = candidate(
            name: "BLÜMCHEN - 90s ICON V4 (Blümchen, Jaro Omar, Niko Mohr).mp3",
            role: .unknown,
            modifiedAt: baseDate,
            version: 4,
            ext: "mp3",
            duration: 200
        )
        let ranked = ranker.rank([demo, cubaseMix], projectContext: context)
        XCTAssertEqual(
            ranked.first?.fileName,
            "BLÜMCHEN - 90s ICON V4 (Blümchen, Jaro Omar, Niko Mohr).mp3"
        )
    }

    func testCPRAnchorDemotesDemoV06BelowTitleMatchedV4Mix() {
        let context = PreviewRankingProjectContext(anchorCPRVersion: 4, titleTokens: ["90s", "icon"])
        let demo = candidate(
            name: "demo v0.6.mp3",
            role: .unknown,
            modifiedAt: baseDate.addingTimeInterval(100),
            version: nil,
            ext: "mp3",
            duration: 200
        )
        let anchoredMix = candidate(
            name: "90s ICON v4 mix.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 4,
            ext: "wav",
            duration: 200
        )
        let ranked = ranker.rank([demo, anchoredMix], projectContext: context)
        XCTAssertEqual(ranked.first?.fileName, "90s ICON v4 mix.wav")
        XCTAssertTrue(ranked.first?.confidenceReasons.contains("cpr-anchor:version-match") == true)
        XCTAssertTrue(demo.confidenceReasons.contains("cpr-anchor:demo-below-project") == false)
        let scoredDemo = ranked.first { $0.fileName == "demo v0.6.mp3" }
        XCTAssertTrue(scoredDemo?.confidenceReasons.contains("cpr-anchor:demo-below-project") == true)
    }

    func testCPRAnchorStillPicksBestAvailableWhenOnlyEarlyDemoExists() {
        let context = PreviewRankingProjectContext(anchorCPRVersion: 4, titleTokens: ["90s", "icon"])
        let demo = candidate(
            name: "demo v0.6.mp3",
            role: .unknown,
            modifiedAt: baseDate,
            version: nil,
            ext: "mp3",
            duration: 200
        )
        let ranked = ranker.rank([demo], projectContext: context)
        XCTAssertEqual(ranked.first?.fileName, "demo v0.6.mp3")
    }

    func testConfidenceReasonsAreDeterministicAndOrdered() {
        let main = candidate(
            name: "Demo v2 mixdown.wav",
            role: .mainMix,
            modifiedAt: baseDate,
            version: 2,
            ext: "wav",
            duration: 210
        )
        let ranked = ranker.rank([main])
        let reasons = ranked.first?.confidenceReasons ?? []
        XCTAssertEqual(
            reasons,
            [
                "maturity:mix",
                "role:full-mix",
                "folder:mixdown",
                "version:v2",
                "extension:wav",
                "duration:plausible",
                "recency",
            ]
        )
    }

    // MARK: - Helpers

    private func candidate(
        name: String,
        role: PreviewDetectedRole,
        modifiedAt: Date,
        version: Int?,
        ext: String,
        duration: Double?
    ) -> PreviewCandidate {
        let folder = URL(fileURLWithPath: "/tmp/fixture/Mixdown", isDirectory: true)
        let url = folder.appendingPathComponent(name)
        return PreviewCandidate(
            filePath: url,
            fileName: name,
            folderRole: .mixdown,
            modifiedAt: modifiedAt,
            detectedRole: role,
            fileExtension: ext,
            detectedVersionNumber: version,
            durationSeconds: duration
        )
    }
}
