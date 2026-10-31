import AppCore
import AppKit
import NikoMusicCore
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveBoardDropLandingTests: XCTestCase {
    /// The copy starts where the pointer let go, the row waits hidden under it,
    /// and when the copy arrives the row takes over with the landed pill.
    func testCopyFliesFromTheReleaseIntoTheHiddenRowThenTheRowTakesOver() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let song = fixture.songs[2]
        let released = CGRect(x: 120, y: 300, width: ArchiveBoardLaneLayout.rowWidth, height: 50)
        let landed = expectation(description: "landing finished")

        ArchiveBoardDropLanding.land(song, releasedAt: (frame: released, view: fixture.host), into: fixture.list,
                                     over: fixture.host, colorScheme: .dark, reduceMotion: false) { landed.fulfill() }

        let copy = try XCTUnwrap(fixture.host.subviews.last as? ArchiveBoardLandingCopy)
        XCTAssertEqual(copy.frame, released, "the copy replaces the drag image where it was let go")
        XCTAssertEqual(fixture.cell(song.id)?.alphaValue, 0, "the row waits hidden while the copy flies")
        let target = try XCTUnwrap(fixture.list.landingFrame(songID: song.id, in: fixture.host))

        wait(for: [landed], timeout: 2)
        XCTAssertNil(copy.superview)
        XCTAssertEqual(copy.frame.origin.x, target.origin.x, accuracy: 0.5)
        XCTAssertEqual(copy.frame.origin.y, target.origin.y, accuracy: 0.5)
        XCTAssertEqual(fixture.cell(song.id)?.alphaValue, 1)
        XCTAssertEqual(fixture.rowView(song.id)?.showsLandedMark, true)
    }

    func testReduceMotionShowsTheRowInPlaceWithoutAFlight() {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let song = fixture.songs[2]
        let landed = expectation(description: "landing finished")
        let before = fixture.host.subviews.count

        ArchiveBoardDropLanding.land(song, releasedAt: (frame: CGRect(x: 0, y: 0, width: 204, height: 50), view: fixture.host),
                                     into: fixture.list, over: fixture.host, colorScheme: .dark, reduceMotion: true) { landed.fulfill() }

        XCTAssertEqual(fixture.host.subviews.count, before, "no flying copy under Reduce Motion")
        wait(for: [landed], timeout: 2)
        XCTAssertEqual(fixture.cell(song.id)?.alphaValue, 1)
        XCTAssertEqual(fixture.rowView(song.id)?.showsLandedMark, true)
    }

    func testShortHopsLandQuickerThanLongFlightsWithinBounds() {
        XCTAssertEqual(ArchiveBoardDropLanding.flightDuration(distance: 0), 0.2, accuracy: 0.001)
        XCTAssertLessThan(ArchiveBoardDropLanding.flightDuration(distance: 150),
                          ArchiveBoardDropLanding.flightDuration(distance: 600))
        XCTAssertEqual(ArchiveBoardDropLanding.flightDuration(distance: 5_000), 0.36, accuracy: 0.001)
    }

    /// The hand-off at the end of a flight is invisible only if the copy and
    /// the landed row (resting row on the lane, under the landed pill) draw the
    /// same pixels: same text, wrap, marks, insets and pill.
    func testCopyDrawsTheSamePixelsAsTheLandedRow() throws {
        let candidate = PreviewCandidate(filePath: URL(fileURLWithPath: "/fixture-only/landing.wav"), fileName: "landing.wav",
                                         folderRole: .mixdown, modifiedAt: .distantPast, detectedRole: .mainMix)
        let songs = [
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/a"), originalFolderName: "A",
                 displayTitle: "Sun Stays Up Forever", previewCandidates: [candidate], mainPreviewCandidateID: candidate.id),
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/b"), originalFolderName: "B",
                 displayTitle: "CHANIN - LIFE SLOW DIE OLD SKETCH"),
        ]
        for scheme in [ColorScheme.dark, .light] {
            for song in songs {
                let copy = try bitmap(of: ArchiveBoardDragPreview(song: song), scheme: scheme)
                let row = try bitmap(of: LandedRow(song: song), scheme: scheme)
                XCTAssertEqual(copy.pixelsWide, row.pixelsWide, "\(song.effectiveDisplayTitle) \(scheme)")
                XCTAssertEqual(copy.pixelsHigh, row.pixelsHigh, "\(song.effectiveDisplayTitle) \(scheme): same wrap and insets")
                // Measured 2026-10-31: the copy's opaque pill and the row's
                // translucent one blend the corner edge apart by up to 5/255.
                XCTAssertLessThanOrEqual(largestChannelDifference(copy, row), 6.0 / 255,
                                         "\(song.effectiveDisplayTitle) \(scheme)")
            }
        }
    }

    // MARK: Fixtures

    private struct LandedRow: View {
        let song: Song
        var body: some View {
            ArchiveBoardCardView(song: song, isSelected: false,
                                 session: ArchivePreviewSession(capture: AudioCaptureActivity()),
                                 vaultPresentation: nil, onSelect: {}, onOpenDetail: {},
                                 onProjectVaultPrimaryAction: nil, onPlay: {})
                .frame(width: ArchiveBoardLaneLayout.rowWidth)
                .background {
                    // ArchiveBoardCardRow.markLanded: the pill under the row's content.
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.selection)
                        .padding(.bottom, 1)
                }
        }
    }

    /// Draws `view` on the lane's surface, as both appear on the board.
    private func bitmap(of view: some View, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view
            .background(HubDesignSystem.Palette.surface)
            .environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.close() }
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func largestChannelDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
        var largest: CGFloat = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 1 }
                largest = max(largest, abs(p.redComponent - q.redComponent), abs(p.greenComponent - q.greenComponent),
                              abs(p.blueComponent - q.blueComponent), abs(p.alphaComponent - q.alphaComponent))
            }
        }
        return largest
    }

    private func makeFixture() -> Fixture {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let songs = (0..<12).map {
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/Landing-\($0)"), originalFolderName: "Song", displayTitle: "Song \($0)")
        }
        let host = LandingHost(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let list = ArchiveBoardNativeSongListView(frame: NSRect(x: 400, y: 0, width: ArchiveBoardLaneLayout.rowWidth, height: 500))
        host.addSubview(list)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
            viewModel: model, dropLayout: ArchiveBoardDropLayout(), colorScheme: .dark, reduceMotion: false
        ), animated: false)
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        return Fixture(window: window, host: host, list: list, songs: songs)
    }

    private final class LandingHost: NSView, ArchiveBoardColumnFrameSpace {}

    private struct Fixture {
        let window: NSWindow
        let host: NSView
        let list: ArchiveBoardNativeSongListView
        let songs: [Song]

        @MainActor private var table: NSTableView? { list.documentView as? NSTableView }

        @MainActor func cell(_ id: String) -> NSView? {
            songs.firstIndex { $0.id == id }.flatMap { table?.view(atColumn: 0, row: $0, makeIfNecessary: false) }
        }

        @MainActor func rowView(_ id: String) -> ArchiveBoardCardRow? {
            songs.firstIndex { $0.id == id }.flatMap { table?.rowView(atRow: $0, makeIfNecessary: false) as? ArchiveBoardCardRow }
        }
    }
}
