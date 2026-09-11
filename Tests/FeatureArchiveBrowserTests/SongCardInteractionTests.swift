import AppKit
import NikoMusicCore
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class SongCardInteractionTests: XCTestCase {
    func testRowPaddingAndEmptyTransportAreaSelectOnce() throws {
        var selections = 0
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture/song"),
                        originalFolderName: "Fixture song", displayTitle: "Fixture song")
        try withRow(song: song, onSelect: { selections += 1 }) { window in
            // In window coordinates, both points are outside the text and buttons:
            // lower-left row padding, then the empty space beside the transport.
            for point in [CGPoint(x: 3, y: 3), CGPoint(x: 240, y: 18)] {
                let before = selections
                try click(point, in: window)
                XCTAssertEqual(selections, before + 1, "Whole-row click at \(point) must select exactly once")
            }
        }
    }

    func testEmbeddedPlayDoesNotSelectSong() throws {
        var selections = 0
        // A nonexistent fixture URL exercises the transport action without producing audio.
        let url = URL(fileURLWithPath: "/fixture/song/preview.wav")
        let candidate = PreviewCandidate(filePath: url, fileName: "preview.wav", folderRole: .mixdown,
                                         modifiedAt: .distantPast, detectedRole: .mainMix)
        let song = Song(folderPath: url.deletingLastPathComponent(), originalFolderName: "Fixture song",
                        displayTitle: "Fixture song", previewCandidates: [candidate], mainPreviewCandidateID: candidate.id)
        defer { ArchivePreviewPlayback.stopAll() }
        try withRow(song: song, onSelect: { selections += 1 }) { window in
            // The glyph sits at the centre; all four padded corners must also activate it.
            let midY = window.contentView!.bounds.midY
            for point in [CGPoint(x: 269, y: midY - 19), CGPoint(x: 307, y: midY - 19),
                          CGPoint(x: 269, y: midY + 19), CGPoint(x: 307, y: midY + 19)] {
                ArchivePreviewPlayback.stopAll()
                try click(point, in: window)
                XCTAssertEqual(ArchivePreviewSession.shared.preview?.filePath, url, "Padded play target at \(point) must load its preview")
                XCTAssertEqual(selections, 0, "Playing a row preview must not also select the song")
            }
        }
    }

    func testBoardPlayPaddingDoesNotSelectOrOpenCard() throws {
        var plays = 0
        var selections = 0
        var opens = 0
        let candidate = PreviewCandidate(filePath: URL(fileURLWithPath: "/fixture/board.wav"), fileName: "board.wav",
                                         folderRole: .mixdown, modifiedAt: .distantPast, detectedRole: .mainMix)
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture/board"), originalFolderName: "Board song",
                        displayTitle: "Board song", previewCandidates: [candidate], mainPreviewCandidateID: candidate.id)
        ArchivePreviewPlayback.stopAll()
        let card = ArchiveBoardCardView(song: song, isSelected: false, vaultPresentation: nil,
                                       onSelect: { selections += 1 }, onOpenDetail: { opens += 1 },
                                       onProjectVaultPrimaryAction: nil, onPlay: { plays += 1 })
        try withView(card.frame(width: 220)) { window in
            let midY = window.contentView!.bounds.midY
            for point in [CGPoint(x: 167, y: midY - 19), CGPoint(x: 205, y: midY - 19),
                          CGPoint(x: 167, y: midY + 19), CGPoint(x: 205, y: midY + 19)] {
                try click(point, in: window)
            }
            XCTAssertEqual(plays, 4)
            XCTAssertEqual(selections, 0)
            XCTAssertEqual(opens, 0)
            try click(CGPoint(x: 40, y: midY), in: window)
            XCTAssertEqual(selections, 1, "Card selection should respond to the first click")
            try click(CGPoint(x: 40, y: midY), in: window)
            XCTAssertEqual(opens, 1, "Double-clicking the title area still opens detail")
            XCTAssertEqual(plays, 4)
        }
    }

    private func withRow(song: Song, onSelect: @escaping () -> Void,
                         perform: (NSWindow) throws -> Void) rethrows {
        try withView(SongCardView(
            song: song, isSelected: false, onSelect: onSelect,
            onWorkflowStatusChange: { _ in }
        ).frame(width: 320), perform: perform)
    }

    private func withView<Content: View>(_ view: Content, perform: (NSWindow) throws -> Void) rethrows {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 110),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        try perform(window)
    }

    private func click(_ point: CGPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
