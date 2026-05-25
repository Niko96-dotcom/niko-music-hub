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
        let lab = try XCTUnwrap(result.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        let main = try XCTUnwrap(lab.previewCandidates.first)

        XCTAssertEqual(main.fileName, "Lab Song v3 mix.wav")
        XCTAssertTrue(main.confidenceReasons.contains("extension:wav"))
        XCTAssertTrue(main.confidenceReasons.contains(where: { $0 == "version:v3" }))
        XCTAssertFalse(main.confidenceReasons.contains(where: { $0.contains("duration:too-short") }))
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
                "role:full-mix",
                "folder:mixdown",
                "filename:positive",
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
