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
        defer { ArchivePlaybackCoordinator.shared.stopAllPlayback() }
        try withRow(song: song, onSelect: { selections += 1 }) { window in
            try click(CGPoint(x: 25, y: 20), in: window)
            XCTAssertEqual(ArchivePlaybackCoordinator.shared.activeURL, url, "The embedded play button must still receive the click")
            XCTAssertEqual(selections, 0, "Playing a row preview must not also select the song")
        }
    }

    func testWorkflowMenuDoesNotSelectSong() throws {
        var selections = 0
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture/song"),
                        originalFolderName: "Fixture song", displayTitle: "Fixture song")
        try withRow(song: song, onSelect: { selections += 1 }) { window in
            let visibleWindows = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
            try click(CGPoint(x: 285, y: window.contentView!.bounds.height - 18), in: window)
            XCTAssertEqual(selections, 0, "The status control must not also select the song")
            XCTAssertTrue(NSApp.windows.contains { $0.isVisible && !visibleWindows.contains($0.windowNumber) },
                          "The workflow picker must open")
        }
    }

    private func withRow(song: Song, onSelect: @escaping () -> Void,
                         perform: (NSWindow) throws -> Void) rethrows {
        let host = NSHostingView(rootView: SongCardView(
            song: song, isSelected: false, onSelect: onSelect,
            onWorkflowStatusChange: { _ in }
        ).frame(width: 320))
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
