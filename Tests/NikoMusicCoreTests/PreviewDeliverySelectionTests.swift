import XCTest
@testable import NikoMusicCore

final class PreviewDeliverySelectionTests: XCTestCase {
    private let ranker = PreviewConfidenceRanker()

    func testNamedDeliveryBeatsImportedProductionAndTechnicalHandoff() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWAV(root, "Audio/Other song prod v9.wav", seconds: 250)
        try writeWAV(root, "Mixdown/ARTIST - ACTUAL SONG V2 (Writer One, Writer Two).wav", seconds: 180)
        try writeWAV(root, "Mixdown/ARTIST - ACTUAL SONG V3 NO LIM NO CLIP (Writer One, Writer Two).wav", seconds: 190)
        let detected = try PreviewCandidateDetector().detectCandidates(in: root)
        let ranked = ranker.rank(detected)
        XCTAssertEqual(ranked.first?.fileName, "ARTIST - ACTUAL SONG V2 (Writer One, Writer Two).wav")
        XCTAssertEqual(ranked.first?.durationSeconds, 180)
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Camp day 7", mainPreview: ranked.first), "ARTIST - ACTUAL SONG")
    }

    func testArtistTitleExamplesPreserveSpellingAndRemoveOnlyAnnotations() {
        let cases = [
            ("CAMP DAY 3", "RIVER KNOX - UP ON THE ROOFTOP V2 (Writer One, Writer Two. Writer Three).wav", "RIVER KNOX - UP ON THE ROOFTOP"),
            ("couch beat", "MARA VELVET - GLASS TOWN SESSION BOUNCE V2 FASTER & HIGHER (Mara Velvet, Writer).wav", "MARA VELVET - GLASS TOWN"),
            ("NOVA HALE WRITING CAMP", "NOVA HALE - PAPER SUN SESSION BOUNCE V1.mp3", "NOVA HALE - PAPER SUN"),
            ("WRITING CAMP DAY 1", "SOL ARDEN - VITTORIA - DEMO V1 (Sol Arden, Writer).wav", "SOL ARDEN - VITTORIA"),
            ("KESTRAL NINE ALONE", "KESTREL NINE - COLD ABOUT IT.wav", "KESTREL NINE - COLD ABOUT IT"),
            ("LUMEN", "LUMEN - st_rlight DEMO V2 Lumen, Writer Two, Writer Three).wav", "LUMEN - st_rlight"),
            ("VANTA 4", "VANTA - I NEVER WANTED THIS MUCH DEMO V1 (Vanta, Writer).mp3", "VANTA - I NEVER WANTED THIS MUCH"),
            ("Camp", "Another Artist - 99 Red Stars V12 (Writer One, Writer Two).wav", "Another Artist - 99 Red Stars")
        ]
        for (folder, file, expected) in cases {
            let ranked = ranker.rank([candidate(file)])
            XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: folder, mainPreview: ranked.first), expected)
        }
    }

    func testLatestVersionWinsAcrossDeliveryLabelsFormatsAndShorterSongLengths() {
        let old = candidate("ARTIST - TITLE prod V1.wav", seconds: 240, date: 100)
        let new = candidate("ARTIST - TITLE V2.mp3", seconds: 180, date: 200)
        let cropped = candidate("ARTIST - TITLE master V99.wav", seconds: 5, date: 300)
        let technical = candidate("ARTIST - TITLE V100 NO LIMITER.wav", seconds: 240, date: 400)
        XCTAssertEqual(ranker.rank([old, cropped, technical, new]).first?.id, new.id)
        // A re-copied older version must not override an explicit newer revision.
        let copiedOld = candidate("ARTIST - TITLE demo V1.wav", seconds: 240, date: 500)
        XCTAssertEqual(ranker.rank([copiedOld, new]).first?.id, new.id)
    }

    func testFullLengthUnlabelledBounceBeatsShortNamedSample() {
        let sample = candidate("Sample Maker - Transition Up.wav", seconds: 14, date: 300)
        let song = candidate("Song Wednesday V4.wav", seconds: 133, date: 100)
        XCTAssertEqual(ranker.rank([sample, song]).first?.id, song.id)
    }

    func testVersionsAreNotComparedAcrossDifferentSongOrApproachNames() {
        let alternate = candidate("ARTIST - TITLE alternate approach V8.wav", date: 100)
        let demo = candidate("ARTIST - TITLE demo V2.wav", date: 200)
        let olderDemo = candidate("ARTIST - TITLE demo V1.wav", date: 300)
        for order in [[alternate, demo, olderDemo], [olderDemo, alternate, demo], [demo, olderDemo, alternate]] {
            let ranked = ranker.rank(order)
            XCTAssertEqual(ranked.first?.id, demo.id)
        }
    }

    func testProjectSaveVersionDoesNotOverrideLaterNamedDeliveryRevision() {
        let context = PreviewRankingProjectContext(anchorCPRVersion: 4, titleTokens: ["title"])
        let v4 = candidate("ARTIST - TITLE demo V4.wav", date: 100)
        let v5 = candidate("ARTIST - TITLE V5.wav", date: 200)
        XCTAssertEqual(ranker.rank([v4, v5], projectContext: context).first?.id, v5.id)
    }

    func testSampleAndDAWTrackNamesDoNotBecomeArtistTitles() {
        for file in ["FX 2 - VocalSynth.wav", "Kit 2 - 130 Bpm Aminor 10-Wavetable.wav", "Bounce CHORUS - Audio [2026-09-04 175705].wav", "Clark Audio - Lost Drum Loop - 96BPM Snare.wav"] {
            XCTAssertNil(PreviewSongIdentity.parse(file), file)
        }
        for name in ["REAL ARTIST - TITLE instrumental.wav", "REAL ARTIST - TITLE (Vocals).wav", "REAL ARTIST - TITLE (Bass).wav"] {
            XCTAssertTrue(PreviewFilenameSemantics.isPartialExport(in: name), name)
        }
        let file = "REAL ARTIST - Drums In My Heart DEMO V2.wav"
        XCTAssertEqual(PreviewCandidateDetector.detectedRole(from: file), .mainMix)
        XCTAssertEqual(PreviewCandidateDetector.detectedRole(from: "REAL ARTIST - Drums In My Heart DEMO V2 (Vocals).wav"), .acapella)
        XCTAssertEqual(PreviewCandidateDetector.detectedRole(from: "REAL ARTIST - Drums In My Heart DEMO V2 (Keyboard).wav"), .stems)
    }

    func testVersionParserIgnoresTakeCountersDatesAndWriterNumbers() {
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "Song demo v2 (Camp day 99)_24.wav"), 2)
        XCTAssertNil(PreviewFilenameParser.parseVersionNumber(from: "CHORUS_99.wav"))
        XCTAssertNil(PreviewFilenameParser.parseVersionNumber(from: "Bounce CHORUS [2026-09-04 175705].wav"))
    }

    func testCachedSelectionRefreshesTitleAndPreservesVirtualTitleAndIgnoredChoices() {
        let old = candidate("Old production prod.wav")
        let delivery = candidate("ARTIST - TITLE demo V2.wav")
        let ignored = candidate("ARTIST - TITLE demo V3.wav")
        var song = Song(folderPath: URL(fileURLWithPath: "/tmp/Camp"), originalFolderName: "Camp", displayTitle: "Camp", previewCandidates: [old, delivery, ignored], mainPreviewCandidateID: old.id)
        song.virtualTitle = "My custom label"
        song.ignoredPreviewCandidateIDs = [ignored.id]
        let refreshed = PreviewAutoSelectionNormalizer.normalized(song)
        XCTAssertEqual(refreshed.mainPreviewCandidateID, delivery.id)
        XCTAssertEqual(refreshed.displayTitle, "ARTIST - TITLE")
        XCTAssertEqual(refreshed.effectiveDisplayTitle, "My custom label")
        song.previewSelectionMode = .manual
        XCTAssertEqual(PreviewAutoSelectionNormalizer.normalized(song).mainPreviewCandidateID, old.id)
    }

    func testDurationReadsOddMetadataAndExtendedFormatChunks() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWAV(root, "extended.wav", seconds: 132)
        XCTAssertEqual(PreviewWAVDurationReader.durationSeconds(for: root.appendingPathComponent("extended.wav")), 132)
        try Data("RIFFbroken".utf8).write(to: root.appendingPathComponent("bad.wav"))
        XCTAssertNil(PreviewWAVDurationReader.durationSeconds(for: root.appendingPathComponent("bad.wav")))
    }

    private func candidate(_ name: String, seconds: Double? = 180, date: Double = 100) -> PreviewCandidate {
        PreviewCandidate(filePath: URL(fileURLWithPath: "/tmp/Mixdown/\(name)"), fileName: name, folderRole: .mixdown, modifiedAt: Date(timeIntervalSince1970: date), detectedRole: PreviewCandidateDetector.detectedRole(from: name), detectedVersionNumber: PreviewFilenameParser.parseVersionNumber(from: name), durationSeconds: seconds)
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("delivery-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeWAV(_ root: URL, _ relative: String, seconds: UInt32) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        func u32(_ value: UInt32) -> Data { var little = value.littleEndian; return withUnsafeBytes(of: &little) { Data($0) } }
        var body = Data("WAVEJUNK".utf8)
        body.append(u32(3)); body.append(contentsOf: [0, 0, 0, 0])
        body.append(Data("fmt ".utf8)); body.append(u32(18))
        body.append(contentsOf: [1, 0, 1, 0])
        body.append(u32(8000)); body.append(u32(16000)); body.append(contentsOf: [2, 0, 16, 0, 0, 0])
        body.append(Data("data".utf8)); body.append(u32(seconds * 16000))
        var header = Data("RIFF".utf8); header.append(u32(UInt32(body.count) + seconds * 16000)); header.append(body)
        try header.write(to: url)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(header.count) + UInt64(seconds * 16000))
        try file.close()
    }
}
