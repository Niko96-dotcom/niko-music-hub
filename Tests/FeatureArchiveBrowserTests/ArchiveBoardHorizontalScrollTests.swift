import AppKit
import NikoMusicCore
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveBoardHorizontalScrollTests: XCTestCase {
    func testUnrelatedScrollAndBoundsNotificationsDoNotMarkBoardAsScrolling() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let activity = fixture.controller.activity
        let unrelated = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        // Even a hosted control inside the document is not a registered lane.
        // Descendant filtering after a process-wide callback is insufficient.
        let document = try XCTUnwrap(fixture.scroll.documentView)
        for parent in [NSView(), document] {
            parent.addSubview(unrelated)
            activity.endIfIdle(at: Date.distantFuture)
            postScrollNotifications(unrelated)
            XCTAssertFalse(activity.isScrolling)
            unrelated.removeFromSuperview()
        }
    }

    func testOnlyOwnedViewportAndLaneSendersMarkScrollingAndDetachRemovesObservers() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let activity = fixture.controller.activity
        let document = try XCTUnwrap(fixture.scroll.documentView)
        let laneHost = try XCTUnwrap(document.subviews.first)
        let lane = try XCTUnwrap(descendants(laneHost).compactMap { $0 as? ArchiveBoardNativeSongListView }.first)
        for scroll in [fixture.scroll as NSScrollView, lane] {
            XCTAssertTrue(scroll.contentView.postsBoundsChangedNotifications)
            for (name, sender) in scrollNotifications(scroll) {
                activity.endIfIdle(at: Date.distantFuture)
                NotificationCenter.default.post(name: name, object: sender)
                XCTAssertTrue(activity.isScrolling, "Missing owned sender for \(name)")
            }
        }
        laneHost.removeFromSuperview()
        activity.endIfIdle(at: Date.distantFuture)
        postScrollNotifications(lane)
        XCTAssertFalse(activity.isScrolling, "Removed lane must stop observing")
        document.addSubview(laneHost)
        activity.endIfIdle(at: Date.distantFuture)
        postScrollNotifications(lane)
        XCTAssertTrue(activity.isScrolling, "Reattached lane must resume observing")

        fixture.window.contentView = nil
        activity.endIfIdle(at: Date.distantFuture)
        postScrollNotifications(fixture.scroll)
        postScrollNotifications(lane)
        XCTAssertFalse(activity.isScrolling, "Detached board and lanes must stop observing")
        fixture.window.contentView = fixture.scroll
        activity.endIfIdle(at: Date.distantFuture)
        postScrollNotifications(fixture.scroll)
        XCTAssertTrue(activity.isScrolling, "Reattached viewport must resume observing")
    }

    func testScrollObservationIsReleasedAndUnregistersOnDeinit() {
        let activity = ArchiveBoardScrollActivity()
        let scroll = NSScrollView()
        var observation: ArchiveBoardScrollObservation? = ArchiveBoardScrollObservation(scrollView: scroll, activity: activity)
        weak let released = observation
        observation = nil
        XCTAssertNil(released)
        postScrollNotifications(scroll)
        XCTAssertFalse(activity.isScrolling)
    }

    private func scrollNotifications(_ scroll: NSScrollView) -> [(Notification.Name, NSView)] {
        [(NSScrollView.willStartLiveScrollNotification, scroll),
         (NSScrollView.didLiveScrollNotification, scroll),
         (NSView.boundsDidChangeNotification, scroll.contentView)]
    }

    private func postScrollNotifications(_ scroll: NSScrollView) {
        for (name, sender) in scrollNotifications(scroll) {
            NotificationCenter.default.post(name: name, object: sender)
        }
    }

    func testHorizontalOffsetMovesDocumentWithoutReplacingExistingColumnHosts() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let document = try XCTUnwrap(fixture.scroll.documentView)
        let columns = document.subviews.map(ObjectIdentifier.init)
        XCTAssertEqual(columns.count, 8)
        XCTAssertTrue(document.subviews.allSatisfy { $0 is any ArchiveBoardColumnFrameSpace },
                      "The document must contain the existing column hosts directly, without another SwiftUI hosting graph")
        XCTAssertEqual(document.frame.width, 1_830, accuracy: 1)
        for step in 1...40 {
            fixture.scroll.contentView.scroll(to: NSPoint(x: step * 12, y: 0))
            fixture.scroll.reflectScrolledClipView(fixture.scroll.contentView)
            fixture.scroll.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(fixture.scroll.contentView.bounds.minX, 480, accuracy: 1)
        XCTAssertEqual(document.subviews.map(ObjectIdentifier.init), columns)
        XCTAssertEqual(document.frame.height, fixture.scroll.contentView.bounds.height, accuracy: 1)
    }

    func testCompactDropExpansionAndResizeUpdateNativeExtent() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let emptyIDs = Set(fixture.columns.dropFirst().map(\.id))
        fixture.scroll.apply(input(fixture, compactIDs: emptyIDs))
        fixture.window.setContentSize(NSSize(width: 500, height: 350))
        fixture.scroll.layoutSubtreeIfNeeded()
        let document = try XCTUnwrap(fixture.scroll.documentView)
        XCTAssertEqual(document.frame.width, 682, accuracy: 1)
        let lane = try XCTUnwrap(document.subviews[1] as? ArchiveBoardDropHostingView<ArchiveBoardColumnContent>)
        lane.targeted(true)
        fixture.scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(document.frame.width, 846, accuracy: 1)
        XCTAssertEqual(lane.frame.width, 220, accuracy: 1)
        lane.targeted(false)
        fixture.scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(document.frame.width, 682, accuracy: 1)
        XCTAssertEqual(lane.frame.width, 56, accuracy: 1)
        XCTAssertEqual(document.frame.height, fixture.scroll.contentView.bounds.height, accuracy: 1)
    }

    func testSelectionMetadataVisibilityAndLatestInteractionReachRetainedNativeColumns() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let document = try XCTUnwrap(fixture.scroll.documentView)
        let identities = document.subviews.map(ObjectIdentifier.init)
        let lane = try XCTUnwrap(document.subviews.first as? ArchiveBoardDropHostingView<ArchiveBoardColumnContent>)
        let oldInteraction = lane.rootView.onInteract
        var columns = fixture.columns
        columns[0].songs[0].virtualTitle = "Updated title"
        let selected = columns[0].songs[0]
        let state = ArchiveBoardLaneState(selectedSong: selected, vaultPresentations: [:],
                                          vaultActivity: [selected.id: "Copying"], isBoardVisible: true)
        var interactions = 0
        fixture.scroll.apply(input(fixture, columns: columns, state: state, onInteract: { interactions += 10 }))
        fixture.scroll.layoutSubtreeIfNeeded()
        let list = try XCTUnwrap(descendants(lane).compactMap { $0 as? ArchiveBoardNativeSongListView }.first)
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ArchiveBoardCardCell)
        XCTAssertEqual(cell.displayedContent?.card.song.virtualTitle, "Updated title")
        XCTAssertEqual(cell.displayedContent?.card.isSelected, true)
        XCTAssertEqual(cell.displayedContent?.card.vaultActivityMessage, "Copying")
        XCTAssertTrue(cell.displayedContent?.card.scrollActivity === fixture.controller.activity)
        oldInteraction()
        XCTAssertEqual(interactions, 10)
        let hidden = ArchiveBoardLaneState(selectedSong: selected, vaultPresentations: [:], vaultActivity: [:], isBoardVisible: false)
        fixture.scroll.apply(input(fixture, columns: columns, state: hidden))
        XCTAssertTrue(document.subviews.allSatisfy(\.isHidden))
        XCTAssertFalse(lane.rootView.isBoardVisible, "Hidden lanes must receive current values rather than retaining an old catalog snapshot")
        fixture.scroll.apply(input(fixture, columns: columns, state: state))
        fixture.scroll.layoutSubtreeIfNeeded()
        XCTAssertFalse(document.subviews.contains(where: \.isHidden))
        XCTAssertEqual(document.subviews.map(ObjectIdentifier.init), identities)
    }

    func testDragOriginsUseLiveClipOffsetAndScrollTargetsAreClamped() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 300))
        scroll.documentView = document
        let controller = ArchiveBoardScrollController()
        controller.scrollView = scroll
        let lane = NSView(frame: NSRect(x: 230, y: 0, width: 220, height: 300))
        let last = NSView(frame: NSRect(x: 1_000, y: 0, width: 200, height: 300))
        document.addSubview(lane)
        document.addSubview(last)
        controller.register(lane, columnID: "lane")
        controller.register(last, columnID: "last")
        controller.scroll(to: "lane", animated: false)
        XCTAssertEqual(scroll.contentView.bounds.minX, 230, accuracy: 1)
        XCTAssertEqual(controller.columnOrigins()["lane"] ?? -1, 0, accuracy: 1)
        controller.scroll(to: "last", animated: false)
        XCTAssertEqual(scroll.contentView.bounds.minX, 800, accuracy: 1)
        XCTAssertEqual(controller.columnOrigins()["lane"] ?? 0, -570, accuracy: 1)
        controller.isRightToLeft = true
        controller.scroll(to: "lane", animated: false)
        XCTAssertEqual(scroll.contentView.bounds.minX, 50, accuracy: 1)
        XCTAssertEqual(controller.columnOrigins()["lane"] ?? -1, 0, accuracy: 1)
        XCTAssertEqual(controller.pointerX(columnID: "lane", localX: 210) ?? -1, 10, accuracy: 1)
    }

    func testHoverTrackingDoesNotWriteCardStateDuringScrollAndRestoresAfterMomentum() {
        let activity = ArchiveBoardScrollActivity()
        let target = ArchiveBoardHoverTarget.card(songID: "fixture", laneID: nil)
        var values: [Bool] = []
        let change: (Bool) -> Void = { values.append($0) }
        activity.hover(target, inside: true, change: change)
        let start = Date()
        for tick in 0..<60 {
            activity.recordActivity(at: start.addingTimeInterval(Double(tick) / 120))
            activity.hover(target, inside: false, change: change)
            activity.hover(target, inside: true, change: change)
        }
        activity.endIfIdle(at: start.addingTimeInterval(0.6))
        XCTAssertTrue(activity.isScrolling)
        XCTAssertEqual(values, [true, false], "Crossing cards during scroll must not write SwiftUI state")
        activity.endIfIdle(at: start.addingTimeInterval(0.8))
        XCTAssertFalse(activity.isScrolling)
        XCTAssertEqual(values, [true, false, true])
    }

    func testLaneRoutingKeepsOriginalHorizontalEventsAndTerminalMomentumAcrossLanes() {
        let controller = ArchiveBoardScrollController()
        let outer = WheelReceiver()
        controller.scrollView = outer
        let began = wheel(x: -12, y: -2, phase: 1)
        XCTAssertTrue(controller.routeHorizontalWheel(began))
        XCTAssertTrue(outer.events.last === began)
        XCTAssertTrue(controller.routeHorizontalWheel(wheel(x: -1, y: -3, phase: 2)))
        XCTAssertTrue(controller.routeHorizontalWheel(wheel(x: 0, y: 0, phase: 4)))
        XCTAssertTrue(controller.routeHorizontalWheel(wheel(x: -3, y: 0, momentum: 1)))
        XCTAssertTrue(controller.routeHorizontalWheel(wheel(x: 0, y: 0, momentum: 3)))
        XCTAssertFalse(controller.routeHorizontalWheel(wheel(x: 0, y: -12, phase: 1)))
        XCTAssertFalse(controller.routeHorizontalWheel(wheel(x: 0, y: -12)))
        XCTAssertEqual(outer.events.count, 5)
    }

    func testPresentationUsesExplicitEqualityInsteadOfReflectingThroughEverySong() throws {
        let source = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardLanesView.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("struct ArchiveBoardLanesPresentation: Equatable"),
                      "SwiftUI must use the catalog's shared-storage column equality at the native boundary")
    }

    func testCrossingIntoAnotherCardDropsOldHoverCallbacksDuringMomentum() {
        let activity = ArchiveBoardScrollActivity()
        let old = ArchiveBoardHoverTarget.card(songID: "old", laneID: nil)
        let next = ArchiveBoardHoverTarget.card(songID: "next", laneID: nil)
        var oldValues: [Bool] = []
        var nextValues: [Bool] = []
        activity.hover(old, inside: true) { oldValues.append($0) }
        let start = Date()
        activity.recordActivity(at: start)
        activity.hover(next, inside: true) { nextValues.append($0) }
        activity.endIfIdle(at: start.addingTimeInterval(0.3))
        XCTAssertEqual(oldValues, [true, false])
        XCTAssertEqual(nextValues, [true])
    }

    private func wheel(x: Int32, y: Int32, phase: Int64 = 0, momentum: Int64 = 0) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: y, wheel2: x, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return NSEvent(cgEvent: event)!
    }

    func testBoardOffsetNeverEntersSwiftUILayoutAndBothHoverTargetsUseScrollSuppression() throws {
        let lanes = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardLanesView.swift", encoding: .utf8)
        for feedback in ["GeometryReader", "PreferenceKey", "ScrollViewReader"] {
            XCTAssertFalse(lanes.contains(feedback), "Scroll geometry must be read natively during drag only")
        }
        let column = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardColumnView.swift", encoding: .utf8)
        XCTAssertFalse(column.contains("@ObservedObject"), "One observation boundary must supply lane values across the hosting root")
        XCTAssertTrue(lanes.contains("@ObservedObject var viewModel"))
        let viewport = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardHorizontalScroll.swift", encoding: .utf8)
        let activity = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardScrollActivity.swift", encoding: .utf8)
        for source in [viewport, activity] {
            XCTAssertFalse(source.contains("object: nil"), "Board scroll observations must subscribe to exact owned senders")
        }
        XCTAssertTrue(viewport.contains("withTransaction(context.transaction)"), "Accepted-drop motion must cross the native hosting boundary")
        for path in ["ArchiveBoardView.swift", "ArchiveCardPlayButton.swift"] {
            let source = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/" + path, encoding: .utf8)
            XCTAssertTrue(source.contains("ArchiveBoardScrollActivity.updateHover"), path)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func makeFixture() -> Fixture {
        let controller = ArchiveBoardScrollController()
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let songs = (0..<200).map {
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/Song-\($0)"), originalFolderName: "Song", displayTitle: "Song")
        }
        let columns = ArchiveBoardProjection.columns(from: songs)
        let scroll = ArchiveBoardHorizontalScrollView(controller: controller)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        let fixture = Fixture(scroll: scroll, window: window, controller: controller, model: model, columns: columns)
        scroll.apply(input(fixture))
        window.orderFront(nil)
        scroll.layoutSubtreeIfNeeded()
        return fixture
    }

    private func input(_ fixture: Fixture, columns: [ArchiveBoardColumn]? = nil,
                       state: ArchiveBoardLaneState? = nil, compactIDs: Set<String> = [],
                       onInteract: @escaping () -> Void = {}) -> ArchiveBoardHorizontalScroll {
        ArchiveBoardHorizontalScroll(
            controller: fixture.controller,
            presentation: ArchiveBoardLanesPresentation(
                columns: columns ?? fixture.columns, compactColumnIDs: compactIDs,
                colorScheme: .light, reduceMotion: true, layoutDirection: .leftToRight,
                state: state ?? ArchiveBoardLaneState(selectedSong: nil, vaultPresentations: [:], vaultActivity: [:], isBoardVisible: true)
            ),
            viewModel: fixture.model, onInteract: onInteract, locationChanged: { _, _ in }, ended: {}
        )
    }

    private struct Fixture {
        let scroll: ArchiveBoardHorizontalScrollView
        let window: NSWindow
        let controller: ArchiveBoardScrollController
        let model: ArchiveBrowserViewModel
        let columns: [ArchiveBoardColumn]
    }
}

private final class WheelReceiver: NSScrollView {
    var events: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) { events.append(event) }
}
