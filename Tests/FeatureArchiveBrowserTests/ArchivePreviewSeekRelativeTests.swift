import AVFoundation
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchivePreviewSeekRelativeTests: XCTestCase {
    func testSeekRelativeMovesCurrentTime() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-088-seek-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeSilentWAV(seconds: 12, at: url)

        let player = ArchivePreviewPlayer()
        defer { player.forceStop() }
        player.load(url: url, position: 0, autoplay: false)
        let duration = try await waitForDuration(on: player)
        XCTAssertGreaterThan(duration, 10)

        player.seek(to: 3, url: url)
        XCTAssertEqual(player.currentTime, 3, accuracy: 0.2)

        player.seekRelative(5, url: url)
        XCTAssertEqual(player.currentTime, 8, accuracy: 0.2)

        player.seekRelative(-5, url: url)
        XCTAssertEqual(player.currentTime, 3, accuracy: 0.2)

        player.seekRelative(100, url: url)
        XCTAssertEqual(player.currentTime, duration, accuracy: 0.2)
    }

    func testSongMenuOwnsOptionArrowSkip() throws {
        let commands = try featureSource("ArchiveShortcutFocusPolicy.swift")
        let songMenu = try String(
            contentsOfFile: "Sources/NikoMusicHub/Commands/HubSongCommands.swift",
            encoding: .utf8
        )
        let browser = try featureSource("ArchiveBrowserView.swift")

        XCTAssertTrue(songMenu.contains("Button(\"Skip Back 5 Seconds\")"))
        XCTAssertTrue(songMenu.contains("Button(\"Skip Forward 5 Seconds\")"))
        XCTAssertTrue(songMenu.contains(".keyboardShortcut(.leftArrow, modifiers: .option)"))
        XCTAssertTrue(songMenu.contains(".keyboardShortcut(.rightArrow, modifiers: .option)"))
        XCTAssertTrue(songMenu.contains("skipPreviewBack"))
        XCTAssertTrue(songMenu.contains("skipPreviewForward"))
        XCTAssertTrue(songMenu.contains("canSkipPreview"))

        XCTAssertTrue(commands.contains("canSkipPreview"))
        XCTAssertTrue(commands.contains("skipPreviewBack"))
        XCTAssertTrue(commands.contains("skipPreviewForward"))

        XCTAssertTrue(browser.contains("seekRelative(-5"))
        XCTAssertTrue(browser.contains("seekRelative(5"))
        XCTAssertTrue(browser.contains("canSkipPreview:"))
        XCTAssertTrue(browser.contains("allowsSongShortcuts"))
        XCTAssertFalse(browser.contains(".keyboardShortcut(.leftArrow"))
        XCTAssertFalse(browser.contains(".keyboardShortcut(.rightArrow"))
        XCTAssertFalse(browser.contains("onKeyPress(.leftArrow"))
        XCTAssertFalse(browser.contains("onKeyPress(.rightArrow"))
    }

    func testPersistentPlayerWiresSeekRelativeWithoutStealingArrows() throws {
        let player = try featureSource("ArchivePersistentPlayerView.swift")
        XCTAssertTrue(player.contains("gobackward.5"))
        XCTAssertTrue(player.contains("goforward.5"))
        XCTAssertTrue(player.contains("seekRelative(-5"))
        XCTAssertTrue(player.contains("seekRelative(5"))
        XCTAssertTrue(player.contains("Skip back 5 seconds"))
        XCTAssertTrue(player.contains("Skip forward 5 seconds"))
        XCTAssertTrue(player.contains("player.duration > 0"))
        XCTAssertFalse(
            player.contains(".keyboardShortcut(.leftArrow"),
            "Option-arrow skip is owned by Song commands so it cannot double-fire"
        )
        XCTAssertFalse(player.contains(".keyboardShortcut(.rightArrow"))
    }

    func testSkipIsSongMenuOnlyNotContextMenu() throws {
        let contextMenu = try featureSource("SongItemCommands.swift")
        XCTAssertFalse(contextMenu.contains("Skip Back 5 Seconds"))
        XCTAssertFalse(contextMenu.contains("Skip Forward 5 Seconds"))
        XCTAssertFalse(contextMenu.contains("seekRelative("))
    }

    private func waitForDuration(
        on player: ArchivePreviewPlayer,
        attempts: Int = 150
    ) async throws -> Double {
        for _ in 0..<attempts {
            if player.duration > 0, !player.isLoading, player.playbackError == nil {
                return player.duration
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(
            domain: "ArchivePreviewSeekRelativeTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for preview duration"]
        )
    }

    private func makeSilentWAV(seconds: Int, at url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 8_000))
        )
        buffer.frameLength = buffer.frameCapacity
        if let samples = buffer.floatChannelData?[0] {
            samples.initialize(repeating: 0, count: Int(buffer.frameLength))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func featureSource(_ filename: String) throws -> String {
        try String(contentsOfFile: "Sources/FeatureArchiveBrowser/\(filename)", encoding: .utf8)
    }
}
