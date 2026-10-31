import AppCore
import AppKit
import NikoMusicCore
import ProjectVaultRuntime
import SwiftUI
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveBoardNativeSongListTests: XCTestCase {
    func testLaneForwardsLateralWheelUnchangedAndRetainsResponsiveVerticalScrolling() {
        let controller = ArchiveBoardScrollController()
        let receiver = LaneWheelReceiver()
        controller.scrollView = receiver
        let fixture = makeFixture(boardScroll: controller)
        defer { fixture.window.close() }
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                         wheel1: -2, wheel2: -12, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        let event = NSEvent(cgEvent: cg)!
        fixture.list.scrollWheel(with: event)
        XCTAssertTrue(receiver.received === event)
        XCTAssertTrue(ArchiveBoardNativeSongListView.isCompatibleWithResponsiveScrolling)
        XCTAssertEqual(fixture.list.horizontalScrollElasticity, .none)
    }

    func testReusedLaneUnregistersOldBoardActivityAndObservesCurrentOwner() {
        let old = ArchiveBoardScrollController()
        let current = ArchiveBoardScrollController()
        let fixture = makeFixture(boardScroll: old)
        defer { fixture.window.close() }
        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: fixture.songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: true,
            boardScroll: current
        ), animated: false)
        old.activity.endIfIdle(at: Date.distantFuture)
        current.activity.endIfIdle(at: Date.distantFuture)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: fixture.list)
        XCTAssertFalse(old.activity.isScrolling)
        XCTAssertTrue(current.activity.isScrolling)

        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: fixture.songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: true
        ), animated: false)
        current.activity.endIfIdle(at: Date.distantFuture)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: fixture.list.contentView)
        XCTAssertFalse(current.activity.isScrolling, "A lane without a board owner must unsubscribe")
    }

    /// A song detail hides the board, and a song edited there reaches the lane while it
    /// is hidden. Its card must show the edit as soon as the board is visible again
    /// (the detail's Back), not only after the next unrelated refresh.
    func testCardEditedWhileTheBoardIsHiddenShowsTheEditWhenTheBoardReturns() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        func lane(_ songs: [Song], visible: Bool) -> ArchiveBoardNativeSongList {
            ArchiveBoardNativeSongList(
                songs: songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
                viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: true,
                isBoardVisible: visible
            )
        }
        func firstCardTitle() -> String? {
            (table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ArchiveBoardCardCell)?
                .displayedContent?.card.song.effectiveDisplayTitle
        }
        XCTAssertEqual(firstCardTitle(), "Song")

        // The detail opens: the column host hides the lane (`ArchiveBoardDropHostingView`).
        fixture.container.isHidden = true
        fixture.list.apply(lane(fixture.songs, visible: false), animated: false)
        var edited = fixture.songs
        edited[0].virtualTitle = "Song Edited"
        fixture.list.apply(lane(edited, visible: false), animated: false)

        // Back: the board shows again with the songs it already has.
        fixture.container.isHidden = false
        fixture.list.apply(lane(edited, visible: true), animated: false)
        fixture.window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(firstCardTitle(), "Song Edited")
    }

    /// The board scrolls lanes sideways out of its viewport. A lane out of view has no
    /// visible rows, but its realized cards must still take a light/dark switch: they
    /// are shown again as they are when the lane scrolls back.
    func testLaneScrolledOutOfViewShowsTheNewColorSchemeWhenItScrollsBack() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        let home = fixture.list.frame
        func lane(_ colorScheme: ColorScheme) -> ArchiveBoardNativeSongList {
            ArchiveBoardNativeSongList(
                songs: fixture.songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
                viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: colorScheme, reduceMotion: true
            )
        }

        // The board scrolls this lane out of its viewport, then the app switches to dark.
        fixture.list.frame = home.offsetBy(dx: -(home.width + 40), dy: 0)
        XCTAssertTrue(table.visibleRect.isEmpty)
        fixture.list.apply(lane(.dark), animated: false)

        // The board scrolls back.
        fixture.list.frame = home
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let rows = table.rows(in: table.visibleRect)
        XCTAssertGreaterThan(rows.length, 0)
        for row in rows.location..<rows.location + rows.length {
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ArchiveBoardCardCell)
            XCTAssertEqual(cell.displayedContent?.colorScheme, .dark, "row \(row)")
        }
    }

    func testEndOfLongLaneIsRealizedAndRowsTouchWithNoTableInsets() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let first = try XCTUnwrap(fixture.layout.frame(for: fixture.songs[0].id))
        let second = try XCTUnwrap(fixture.layout.frame(for: fixture.songs[1].id))
        XCTAssertEqual(first.minX, 0, accuracy: 0.5)
        XCTAssertEqual(first.minY, 0, accuracy: 0.5)
        XCTAssertEqual(second.minY - first.maxY, 0, accuracy: 0.5, "board songs are rows; the hairline sits between them")
        table.scrollRowToVisible(fixture.songs.count - 1)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let last = try XCTUnwrap(fixture.layout.frame(for: fixture.songs.last!.id))
        XCTAssertTrue(last.intersects(fixture.container.bounds))
        XCTAssertGreaterThan(last.height, 0)
    }

    /// Board songs are rows: a hairline between two rows, none under the last
    /// row and none touching the selected row.
    func testHairlinesSitBetweenRowsButNotUnderTheLastOrAroundTheSelection() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        let songs = Array(fixture.songs.prefix(4))
        func lane(selected: Int?) -> ArchiveBoardNativeSongList {
            ArchiveBoardNativeSongList(
                songs: songs, selectedSongID: selected.map { songs[$0].id }, vaultPresentations: [:],
                vaultActivity: [:], viewModel: fixture.model, dropLayout: fixture.layout,
                colorScheme: .light, reduceMotion: true
            )
        }
        func hairlines() -> [Bool] {
            (0..<table.numberOfRows).map {
                (table.rowView(atRow: $0, makeIfNecessary: false) as? ArchiveBoardCardRow)?.showsSeparator ?? false
            }
        }

        fixture.list.apply(lane(selected: nil), animated: false)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(hairlines(), [true, true, true, false])

        fixture.list.apply(lane(selected: 1), animated: false)
        XCTAssertEqual(hairlines(), [false, false, true, false])

        fixture.list.apply(lane(selected: 3), animated: false)
        XCTAssertEqual(hairlines(), [true, true, false, false])
    }

    /// Lanes sort by recent activity, so a drop can land far down a lane:
    /// the moved row is scrolled into sight where it fades in, marked with the
    /// landed pill unless it is selected (its pill is there already).
    func testRevealDroppedSongScrollsItsRowIntoSightAndMarksIt() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(table.rows(in: table.visibleRect).contains(150))

        fixture.list.revealDroppedSong(songID: fixture.songs[150].id, reduceMotion: true)
        XCTAssertTrue(table.rows(in: table.visibleRect).contains(150))
        XCTAssertEqual((table.rowView(atRow: 150, makeIfNecessary: false) as? ArchiveBoardCardRow)?.showsLandedMark, true)
        fixture.list.revealDroppedSong(songID: "not-in-this-lane", reduceMotion: true)
        XCTAssertTrue(table.rows(in: table.visibleRect).contains(150))

        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: fixture.songs, selectedSongID: fixture.songs[151].id, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: true
        ), animated: false)
        fixture.list.revealDroppedSong(songID: fixture.songs[151].id, reduceMotion: true)
        XCTAssertEqual((table.rowView(atRow: 151, makeIfNecessary: false) as? ArchiveBoardCardRow)?.showsLandedMark, false)
    }

    func testRealizedCardReceivesLatestMetadataSelectionAndVaultActivity() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        var songs = fixture.songs
        songs[0].virtualTitle = "Updated title"
        songs[0].workflowStatus = .done
        let vault = ProjectVaultCardPresentation(record: ProjectRecord(canonicalTitle: "Song", locations: []))
        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: songs[0].id,
            vaultPresentations: [songs[0].id: vault], vaultActivity: [songs[0].id: "Copying"],
            viewModel: fixture.model, dropLayout: fixture.layout,
            colorScheme: .dark, reduceMotion: true
        ), animated: false)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ArchiveBoardCardCell)
        let content = try XCTUnwrap(cell.displayedContent)
        XCTAssertEqual(content.card.song, songs[0])
        XCTAssertTrue(content.card.isSelected)
        XCTAssertEqual(content.card.vaultActivityMessage, "Copying")
        XCTAssertEqual(content.colorScheme, .dark)
        XCTAssertTrue(content.card.viewModel === fixture.model)
    }

    func testHiddenLaneResetsScrollAndOffscreenEditsAreFreshWhenRealized() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let oldHeight = try XCTUnwrap(fixture.layout.frame(for: fixture.songs[0].id)).height
        table.scrollRowToVisible(fixture.songs.count - 1)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        var songs = fixture.songs
        songs[0].virtualTitle = String(repeating: "Long title ", count: 12)
        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light,
            reduceMotion: true, isBoardVisible: false
        ), animated: false)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(fixture.list.contentView.bounds.minY, 0, accuracy: 0.5)
        // A row's title holds two lines inside the play button's height, so the
        // edit shows in the realized row's song, not in a taller row.
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ArchiveBoardCardCell)
        XCTAssertEqual(cell.displayedContent?.card.song, songs[0])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(fixture.layout.frame(for: songs[0].id)).height, oldHeight)
        XCTAssertTrue(fixture.list.documentView === table)
    }

    func testMembershipChangesAndInteractionOwnerReachReusedRows() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        var songs = Array(fixture.songs.dropFirst())
        let added = Song(folderPath: URL(fileURLWithPath: "/fixture-only/Added"), originalFolderName: "Added", displayTitle: "Added")
        songs.append(added)
        var interactions = 0
        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: added.id, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: false,
            onInteract: { interactions += 1 }
        ), animated: true)
        let table = try XCTUnwrap(fixture.list.documentView as? NSTableView)
        table.scrollRowToVisible(songs.count - 1)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: songs.count - 1, makeIfNecessary: false) as? ArchiveBoardCardCell)
        let content = try XCTUnwrap(cell.displayedContent)
        XCTAssertEqual(content.card.song, added)
        content.interaction.perform()
        XCTAssertEqual(interactions, 1)
        fixture.list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: added.id, vaultPresentations: [:], vaultActivity: [:],
            viewModel: fixture.model, dropLayout: fixture.layout, colorScheme: .light, reduceMotion: true,
            onInteract: { interactions += 10 }
        ), animated: false)
        content.interaction.perform()
        XCTAssertEqual(interactions, 11)
        XCTAssertEqual(table.numberOfRows, songs.count)
    }

    private func makeFixture(boardScroll: ArchiveBoardScrollController? = nil) -> Fixture {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let songs = (0..<200).map {
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/Song-\($0)"), originalFolderName: "Song", displayTitle: "Song")
        }
        let layout = ArchiveBoardDropLayout()
        let container = ColumnFrameSpace(frame: NSRect(x: 0, y: 0, width: 204, height: 508))
        let list = ArchiveBoardNativeSongListView(frame: container.bounds)
        container.addSubview(list)
        let window = NSWindow(contentRect: container.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        list.apply(ArchiveBoardNativeSongList(
            songs: songs, selectedSongID: nil, vaultPresentations: [:], vaultActivity: [:],
            viewModel: model, dropLayout: layout, colorScheme: .light, reduceMotion: true,
            boardScroll: boardScroll
        ), animated: false)
        window.orderFront(nil)
        return Fixture(window: window, container: container, list: list, songs: songs, layout: layout, model: model)
    }

    private struct Fixture {
        let window: NSWindow
        let container: NSView
        let list: ArchiveBoardNativeSongListView
        let songs: [Song]
        let layout: ArchiveBoardDropLayout
        let model: ArchiveBrowserViewModel
    }
}

private final class LaneWheelReceiver: NSScrollView {
    var received: NSEvent?
    override func scrollWheel(with event: NSEvent) { received = event }
}

private final class ColumnFrameSpace: NSView, ArchiveBoardColumnFrameSpace {
    override var isFlipped: Bool { true }
}
