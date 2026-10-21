import AppCore
import AVFoundation
import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchivePreviewSessionTests: XCTestCase {
    func testPausedPlayerFollowsSelectionBetweenTrailingSpaceAndSuffixFolders() async throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = fixture.songs
        model.filteredSongs = fixture.songs
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        let first = fixture.songs[0]
        let second = fixture.songs[1]
        model.selectSongOnBoard(second)
        model.audition(second)
        session.player.pause()
        try await ready(session.player)
        session.player.seek(to: 1, url: second.mainPreviewURL)

        model.selectSongOnBoard(first)

        XCTAssertEqual(model.selectedSong?.id, first.id)
        XCTAssertEqual(session.songID, first.id, "A paused bar must follow the highlighted card")
        XCTAssertEqual(session.songTitle, first.effectiveDisplayTitle)
        XCTAssertEqual(session.preview?.filePath, first.mainPreviewURL)
        XCTAssertEqual(session.player.activeURL, first.mainPreviewURL)
        XCTAssertEqual(session.player.currentTime, 0)
        XCTAssertFalse(session.isPlaying, "Selecting a card must not start audio")
        session.toggle() // The persistent bar's Play action.
        XCTAssertEqual(session.player.activeURL, first.mainPreviewURL)
        XCTAssertTrue(session.isPlaying)
    }

    func testPlayingTrackSurvivesBrowsingAndPauseThenArmsSelection() async throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        model.audition(fixture.songs[1])
        model.selectSongOnBoard(fixture.songs[0])
        XCTAssertEqual(session.songID, fixture.songs[1].id)
        XCTAssertTrue(session.isPlaying)

        session.player.pause()
        let deadline = Date().addingTimeInterval(5)
        while session.songID != fixture.songs[0].id, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.songID, fixture.songs[0].id)
        XCTAssertEqual(session.player.activeURL, fixture.songs[0].mainPreviewURL)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.currentTime, 0)
    }

    func testImmediateBarResumeAndExplicitCardAuditionChooseTheirOwnTargets() throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        let first = fixture.songs[0]
        let second = fixture.songs[1]
        model.audition(second)
        model.selectSongOnBoard(first)
        session.player.pause()
        // No run-loop turn between pause and the bar action: do not replay stale audio.
        session.toggle()
        XCTAssertEqual(session.player.activeURL, first.mainPreviewURL)
        XCTAssertTrue(session.isPlaying)

        // Card Play has an explicit target even while another song is highlighted.
        model.audition(second)
        XCTAssertEqual(session.player.activeURL, second.mainPreviewURL)
        session.player.pause()
        model.audition(second)
        XCTAssertEqual(session.player.activeURL, second.mainPreviewURL)
        XCTAssertTrue(session.isPlaying)
    }

    func testSelectingSongWithoutPreviewClearsPausedTransportAndDoesNotAutoplay() throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        model.audition(fixture.songs[1])
        session.player.pause()
        var noPreview = fixture.songs[0]
        noPreview.previewCandidates = []
        noPreview.mainPreviewCandidateID = nil
        model.selectSong(noPreview)
        XCTAssertNil(session.preview)
        XCTAssertNil(session.songID)
        XCTAssertNil(session.player.activeURL)
        session.toggle()
        XCTAssertFalse(session.isPlaying)
    }

    func testPausedRescanReplacesRemovedPreviewAndRefreshesVirtualTitle() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        model.songs = [fixture.song]
        model.selectSong(fixture.song)
        model.audition(fixture.song)
        session.player.pause()
        try await ready(session.player)
        var refreshed = fixture.song
        refreshed.previewCandidates = [fixture.previews[1]]
        refreshed.mainPreviewCandidateID = fixture.previews[1].id
        refreshed.virtualTitle = "My renamed song"
        model.songs = [refreshed]
        model.reconcileSelectedSong(requireVisibleInFilteredList: false)
        XCTAssertEqual(session.preview?.id, fixture.previews[1].id)
        XCTAssertEqual(session.songTitle, "My renamed song")
        XCTAssertEqual(session.player.activeURL, fixture.previews[1].filePath)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.currentTime, 0)
        model.clearSelection(stopPlayback: false)
        session.openSong()
        XCTAssertEqual(model.selectedSong?.id, refreshed.id, "The bar still opens its own song after deselection")
    }

    func testRecordingDefersSelectionBindingAndNeverResumesAudio() throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let capture = AudioCaptureActivity()
        let session = ArchivePreviewSession(capture: capture)
        defer { session.clear() }
        session.audition(song: fixture.songs[1], openSong: {})
        let owner = UUID()
        capture.setActive(true, owner: owner)
        session.followSelection(fixture.songs[0], openSong: {})
        XCTAssertEqual(session.songID, fixture.songs[1].id)
        session.toggle()
        XCTAssertFalse(session.isPlaying)
        capture.setActive(false, owner: owner)
        XCTAssertEqual(session.songID, fixture.songs[0].id)
        XCTAssertFalse(session.isPlaying)
    }

    func testExactFolderPathsKeepPlayerCachesSnapshotPinsAndVirtualTitlesSeparate() async throws {
        let fixture = try makeHenryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = fixture.songs[0]
        let second = fixture.songs[1]
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(ArchiveMixdownAnalysisCoordinator.cacheKey(for: first), ArchiveMixdownAnalysisCoordinator.cacheKey(for: second))
        ArchivePreviewPlayer.clearMetadataCaches()
        defer { ArchivePreviewPlayer.clearMetadataCaches() }
        let revision = Date.distantPast
        let firstURL = try XCTUnwrap(first.mainPreviewURL)
        let secondURL = try XCTUnwrap(second.mainPreviewURL)
        ArchivePreviewPlayer.storeCachedDurationForTests(3, url: firstURL, modifiedAt: revision)
        ArchivePreviewPlayer.storeCachedDurationForTests(7, url: secondURL, modifiedAt: revision)
        ArchivePreviewPlayer.storeCachedHookForTests(1, url: firstURL, modifiedAt: revision)
        ArchivePreviewPlayer.storeCachedHookForTests(5, url: secondURL, modifiedAt: revision)
        XCTAssertEqual(ArchivePreviewPlayer.cachedDurationForTests(url: firstURL, modifiedAt: revision), 3)
        XCTAssertEqual(ArchivePreviewPlayer.cachedDurationForTests(url: secondURL, modifiedAt: revision), 7)
        XCTAssertEqual(ArchivePreviewPlayer.cachedHookForTests(url: firstURL, modifiedAt: revision), 1)
        XCTAssertEqual(ArchivePreviewPlayer.cachedHookForTests(url: secondURL, modifiedAt: revision), 5)

        let database = try SQLiteArchiveDatabase(databaseURL: fixture.root.appendingPathComponent("fixture.sqlite"))
        let index = try SQLiteArchiveIndexStore(database: database)
        let metadata = try SQLiteSongUserMetadataStore(database: database)
        try index.save(ArchiveIndexSnapshot(roots: [fixture.root.path], songs: fixture.songs, scannedAt: Date()))
        try metadata.upsert(SongUserMetadata(songID: first.id, virtualTitle: "My Day 1", previewSelectionMode: .manual,
                                            manualMainPreviewID: second.mainPreviewCandidateID))
        try metadata.upsert(SongUserMetadata(songID: second.id, virtualTitle: "My Idea 2", previewSelectionMode: .manual,
                                            manualMainPreviewID: second.mainPreviewCandidateID))
        let coordinator = ArchiveCatalogCoordinator(archiveIndexStore: index, songMetadataStore: metadata,
                                                     collaboratorStore: nil, diagnostics: TestToolContext.make().diagnostics)
        guard case .loaded(let songs, _) = await coordinator.loadCachedSongsDetached(roots: [fixture.root], collaborators: []) else {
            return XCTFail("Expected two cached songs")
        }
        XCTAssertEqual(songs.count, 2)
        let loadedFirst = try XCTUnwrap(songs.first { $0.id == first.id })
        let loadedSecond = try XCTUnwrap(songs.first { $0.id == second.id })
        XCTAssertEqual(loadedFirst.mainPreviewURL, firstURL, "A foreign saved pin is refused")
        XCTAssertEqual(loadedFirst.previewSelectionMode, .auto)
        XCTAssertEqual(loadedFirst.effectiveDisplayTitle, "My Day 1")
        XCTAssertEqual(loadedSecond.mainPreviewURL, secondURL)
        XCTAssertEqual(loadedSecond.previewSelectionMode, .manual)
        XCTAssertEqual(loadedSecond.effectiveDisplayTitle, "My Idea 2")
    }

    func testComparisonPreservesPausedTimeAndClampsShorterFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        session.player.pause()
        try await ready(session.player)
        session.player.seek(to: 2, url: fixture.previews[0].filePath)
        session.compare(song: fixture.song, candidate: fixture.previews[1])
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.currentTime, 2, accuracy: 0.15)
        session.compare(song: fixture.song, candidate: fixture.previews[2])
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.duration, 1, accuracy: 0.1)
        XCTAssertEqual(session.player.currentTime, 1, accuracy: 0.15)
    }

    func testDeselectionAndPreviewDefaultKeepSameSongPausedPosition() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = [fixture.song]
        model.filteredSongs = [fixture.song]
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        model.selectSongOnBoard(fixture.song)
        model.audition(fixture.song)
        session.player.pause()
        try await ready(session.player)
        session.player.seek(to: 1, url: fixture.previews[0].filePath)
        model.viewMode = .list
        model.clearSelection(stopPlayback: false)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        XCTAssertEqual(session.player.currentTime, 1, accuracy: 0.1)
        XCTAssertFalse(session.isPlaying)
        model.selectSongOnBoard(fixture.song)
        // A changed default does not discard a valid loaded alternate for this song.
        var changed = fixture.song
        changed.mainPreviewCandidateID = fixture.previews[1].id
        model.songs = [changed]
        model.reconcileSelectedSong()
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        ArchivePreviewPlayback.stopAll()
        XCTAssertNil(session.preview, "A lifecycle reset clears paused audio too")
    }

    func testCapturePausesPendingPlaybackBlocksAuditionAndDoesNotResume() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let capture = AudioCaptureActivity()
        let session = ArchivePreviewSession(capture: capture)
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        let owner = UUID()
        capture.setActive(true, owner: owner)
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        session.toggle()
        session.compare(song: fixture.song, candidate: fixture.previews[1])
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        capture.setActive(false, owner: owner)
        XCTAssertFalse(session.isPlaying)
    }

    func testRapidReplacementAndFailureCannotReviveOldRequest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        session.audition(song: fixture.song, candidate: fixture.previews[1], openSong: {})
        session.player.pause()
        try await ready(session.player)
        XCTAssertEqual(session.player.activeURL, fixture.previews[1].filePath)
        XCTAssertFalse(session.isPlaying)
        let missing = PreviewCandidate(filePath: fixture.root.appendingPathComponent("missing.wav"), fileName: "missing.wav", folderRole: .mixdown, modifiedAt: Date(), detectedRole: .mainMix)
        session.audition(song: fixture.song, candidate: missing, openSong: {})
        let deadline = Date().addingTimeInterval(5)
        while session.player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(session.player.playbackError)
        XCTAssertFalse(session.isPlaying)
        session.audition(song: fixture.song, candidate: fixture.previews[0], openSong: {})
        session.player.pause()
        try await ready(session.player)
        XCTAssertNil(session.player.playbackError)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
    }

    private func ready(_ player: ArchivePreviewPlayer) async throws {
        let deadline = Date().addingTimeInterval(6)
        while player.isLoading, player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(player.playbackError)
        XCTAssertFalse(player.isLoading)
    }

    private func makeFixture() throws -> (root: URL, song: Song, previews: [PreviewCandidate]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/NMHPreview-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previews = try [3, 3, 1].enumerated().map { index, seconds in
            let url = root.appendingPathComponent("mix-\(index).wav")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 8000)))
            buffer.frameLength = buffer.frameCapacity
            if let samples = buffer.floatChannelData?[0] { samples.initialize(repeating: 0, count: Int(buffer.frameLength)) }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return PreviewCandidate(filePath: url, fileName: url.lastPathComponent, folderRole: .mixdown, modifiedAt: Date(), detectedRole: .mainMix)
        }
        return (root, Song(folderPath: root, originalFolderName: "Fixture", displayTitle: "Fixture", previewCandidates: previews, mainPreviewCandidateID: previews[0].id), previews)
    }

    private func makeHenryFixture() throws -> (root: URL, songs: [Song]) {
        let fixture = try makeFixture()
        let names = [
            ("HENRY DAY 1 ", "Sun Stays Up Forever", "sun stays up forever session bounce henry x hailex x niko.wav"),
            ("HENRY DAY 1 IDEA 2", "I Said I Love You First", "i said i love you first session bounce henry x hailey x niko.wav"),
        ]
        let songs = try names.map { folderName, title, fileName in
            let folder = fixture.root.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: fixture.previews[0].filePath, to: url)
            let preview = PreviewCandidate(filePath: url, fileName: fileName, folderRole: .root,
                                           modifiedAt: .distantPast, detectedRole: .mainMix)
            return Song(folderPath: folder, originalFolderName: folderName, displayTitle: title,
                        previewCandidates: [preview], mainPreviewCandidateID: preview.id)
        }
        return (fixture.root, songs)
    }
}
