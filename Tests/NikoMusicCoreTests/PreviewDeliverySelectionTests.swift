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
        for file in ["FX 2 - VocalSynth.wav", "Kit 2 - 130 Bpm Aminor 10-Wavetable.wav", "Bounce CHORUS - Audio [2026-09-04 175705].wav", "Clark Audio - Lost Drum Loop - 96BPM Snare.wav", "Vocals - 01-01%20Good%20Old%20Days.wav", "ADLIP 1 - 01_Voice-Normalize-F6FB024E16BF450FA007C0C784D9F03E.wav", "Render - Voice-F6FB024E16BF450FA007C0C784D9F03E.wav"] {
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

    func testRestoredProjectUsesDeliveryIdentityAndChoosesMixdownOverSourceMedia() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWAV(root, "Audio/Vocals - 01-01%20Good%20Old%20Days.wav", seconds: 180)
        try writeWAV(root, "Audio/IMPORTED ARTIST - OTHER SONG master V99.wav", seconds: 180)
        try writeWAV(root, "Edits/ADLIP 1 - 01_Voice-Normalize-F6FB024E16BF450FA007C0C784D9F03E.wav", seconds: 180)
        try writeWAV(root, "Samples/Imported/OTHER ARTIST - DIFFERENT SONG master V99.wav", seconds: 180)
        try writeWAV(root, "References/OTHER ARTIST - DIFFERENT SONG (Official Video).wav", seconds: 180)
        try writeWAV(root, "Mixdown/Radio demo V1.wav", seconds: 180)
        try writeWAV(root, "Mixdown/Radio demo V2.wav", seconds: 180)
        let versions = [ProjectVersion(filePath: root.appendingPathComponent("Radio-04.cpr"), fileName: "Radio-04.cpr", modifiedAt: .now, detectedVersionNumber: 4)]
        let detected = try PreviewCandidateDetector().detectCandidates(in: root)
        let ranked = ranker.rank(detected, projectContext: .from(projectVersions: versions))
        XCTAssertEqual(ranked.first?.fileName, "Radio demo V2.wav")
        XCTAssertEqual(detected.filter { $0.folderRole == .samples }.count, 3)
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Artist - Radio ", mainPreview: ranked.first, projectVersions: versions), "Radio")

        // The installed app has already cached the wrong role, title and choice.
        // Refresh derived values at startup without requiring a destructive rescan.
        var cached = detected.map { candidate in
            PreviewCandidate(filePath: candidate.filePath, fileName: candidate.fileName,
                             folderRole: .other, modifiedAt: candidate.modifiedAt,
                             detectedRole: .mainMix, detectedVersionNumber: candidate.detectedVersionNumber,
                             durationSeconds: candidate.durationSeconds)
        }
        cached = ranker.rank(cached)
        let wrong = try XCTUnwrap(cached.first { $0.fileName.hasPrefix("Vocals") })
        let song = Song(folderPath: root, originalFolderName: "Artist - Radio ", displayTitle: "Vocals - Wrong Name", projectVersions: versions, previewCandidates: cached, mainPreviewCandidateID: wrong.id)
        let refreshed = PreviewAutoSelectionNormalizer.normalized(song)
        XCTAssertEqual(refreshed.displayTitle, "Radio")
        XCTAssertEqual(refreshed.mainPreviewURL?.lastPathComponent, "Radio demo V2.wav")
    }

    func testNamedReferenceCannotReplaceSongTitleEvenWhenItIsTheOnlyAudio() {
        let reference = PreviewCandidate(filePath: URL(fileURLWithPath: "/tmp/Song/References/OTHER ARTIST - DIFFERENT SONG.wav"),
                                         fileName: "OTHER ARTIST - DIFFERENT SONG.wav", folderRole: .samples,
                                         modifiedAt: .now, detectedRole: .mainMix, durationSeconds: 180)
        let ranked = ranker.rank([reference])
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Seoul", mainPreview: ranked.first), "Seoul")
        XCTAssertFalse(ranked[0].confidenceReasons.contains("filename:artist-title"))
    }

    func testDeliveryTitleParsingPreservesNumbersAndWordsInsideTitles() {
        for (file, expected) in [
            ("404 DEMO V1 (Writer One, Writer Two) new prod.mp3", "404"),
            ("Old Friends DEMO V2.wav", "Old Friends"),
            ("The Master Plan DEMO V2.wav", "The Master Plan"),
            ("The Master Plan.wav", nil),
            ("New Song session bounce V3.wav", "New Song"),
        ] {
            XCTAssertEqual(PreviewSongIdentity.unstructuredDeliveryTitle(file), expected, file)
        }
        XCTAssertEqual(PreviewSongIdentity.parse("ARTIST - The Master Plan DEMO V2.wav")?.displayTitle, "ARTIST - The Master Plan")
        XCTAssertEqual(PreviewSongIdentity.parse("ARTIST - 404 DEMO V2.wav")?.displayTitle, "ARTIST - 404")
    }

    func testNumberedDAWTakesAreNotArtistTitleDeliveriesRegardlessOfTrackLabel() {
        for file in ["Pro-other - 01-01%20Good%20Old%20Days.wav", "Piano - 01-01%20Other%20Song.wav",
                     "MAIN LEAD - 00-01.wav", "HARM 2 L - 00_Voice.wav", "DLX FX - 05.wav",
                     "Arbitrary Track Name - 12_Processed.wav"] {
            XCTAssertNil(PreviewSongIdentity.parse(file), file)
        }
        XCTAssertEqual(PreviewSongIdentity.parse("ARTIST - 404.wav")?.displayTitle, "ARTIST - 404")
        XCTAssertEqual(PreviewSongIdentity.parse("ARTIST - 99 Red Stars.wav")?.displayTitle, "ARTIST - 99 Red Stars")
    }

    func testFullSongEligibilityPrecedesScoresAndVersionNumbers() {
        let demo = candidate("404 DEMO V1.mp3")
        let handoff = candidate("404 for ableton master.wav", date: 999)
        let stem = candidate("ARTIST - 404 V99 (Vocals).wav", date: 999)
        let reference = candidate("OTHER ARTIST - Other Song (Official Video).wav", date: 999)
        let ranked = ranker.rank([handoff, reference, stem, demo], projectContext: .init(anchorCPRVersion: 5, titleTokens: []))
        XCTAssertEqual(ranked.first?.id, demo.id)
        let scoredHandoff = ranked.first { $0.id == handoff.id }!
        XCTAssertGreaterThan(scoredHandoff.confidenceScore, ranked[0].confidenceScore)
        XCTAssertEqual(ranker.decidingFactor(winner: ranked[0], runnerUp: scoredHandoff), .songSuitability)
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Working Session", mainPreview: ranked.first), "404")
        let differentProjectSave = ranker.rank([demo], projectContext: .init(anchorCPRVersion: 99, titleTokens: []))
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Working Session", mainPreview: differentProjectSave.first), "404")
    }

    func testFreshAndPersistedScansResolveDeliveryIdentityWithoutChangingFolderIdentity() throws {
        let library = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: library) }
        let folder = library.appendingPathComponent("Working Session ", isDirectory: true)
        try writeWAV(folder, "Audio/Vocals - 01-Something.wav", seconds: 180)
        try writeWAV(folder, "Mixdown/NEW SONG DEMO V2.wav", seconds: 180)
        try Data().write(to: folder.appendingPathComponent("Working Session-04.cpr"))
        let scanned = try XCTUnwrap(MusicArchiveScanner().scan(roots: [library]).songs.first)
        XCTAssertEqual(scanned.displayTitle, "NEW SONG")
        XCTAssertEqual(try scanned.folderPath.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
                       try folder.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject)
        XCTAssertEqual(scanned.originalFolderName, "Working Session ")
        var stale = scanned
        stale.displayTitle = "Working Session"
        stale.mainPreviewCandidateID = scanned.previewCandidates.first { $0.fileName.hasPrefix("Vocals") }?.id
        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(stale))
        let refreshed = PreviewAutoSelectionNormalizer.normalized(decoded)
        XCTAssertEqual(refreshed.id, scanned.id)
        XCTAssertEqual(refreshed.folderPath, scanned.folderPath)
        XCTAssertEqual(refreshed.displayTitle, scanned.displayTitle)
        XCTAssertEqual(refreshed.mainPreviewURL, scanned.mainPreviewURL)
    }

    func testRealDeliveryInsideCubaseAudioRemainsEligible() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeWAV(root, "Audio/ARTIST - NEW SONG.wav", seconds: 180)
        try writeWAV(root, "Audio/new song idea.wav", seconds: 180)
        try writeWAV(root, "Audio/NEW SONG vox stem.wav", seconds: 180)
        try writeWAV(root, "Audio/ARBITRARY TRACK - 01-01%20Other%20Song.wav", seconds: 180)
        try writeWAV(root, "Audio/DLX FX - 05.wav", seconds: 180)
        let ranked = ranker.rank(try PreviewCandidateDetector().detectCandidates(in: root))
        XCTAssertEqual(ranked.first?.fileName, "ARTIST - NEW SONG.wav")
        XCTAssertEqual(SongTitleResolver().displayTitle(fromFolderName: "Working Session", mainPreview: ranked.first), "ARTIST - NEW SONG")
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
