import AppKit
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveBoardDropHostTests: XCTestCase {
    func testNewRowLayoutIsDoneBeforeTheLandingStarts() {
        let view = ArchiveBoardDropHostingView(rootView: FixtureColumnLayout(showsCard: false))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        var landedOnNewLayout = false
        view.accepts = { $0 == "fixture-song" }
        view.perform = { _, _ in true }
        view.refreshedContent = { FixtureColumnLayout(showsCard: true) }
        view.land = { _ in landedOnNewLayout = view.rootView.showsCard && !view.needsLayout }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertTrue(landedOnNewLayout, "the reveal looks for the new row, so the moved content must be laid out")
    }

    /// AppKit's slide stays off: it ran beside the lanes' row motion and slid
    /// onto a row that had already faded in.
    func testDropValidatesAgainBeforeMutationAndLeavesAppKitsLandingOff() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        var valid = true
        var mutations = 0
        view.accepts = { valid && $0 == "fixture-song" }
        view.perform = { _, _ in mutations += 1; return true }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertFalse(info.animatesToDestination)
        valid = false
        XCTAssertFalse(view.performDragOperation(info))
        XCTAssertEqual(mutations, 0)
    }

    func testAcceptedDropRevealsTheSongAfterMutation() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 600)
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        var moved = false
        var revealed: (id: String, afterMove: Bool)?
        var ended = false
        view.accepts = { $0 == "fixture-song" }
        view.perform = { _, _ in moved = true; return true }
        view.land = { revealed = ($0, moved) }
        view.ended = { ended = true }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertEqual(revealed?.id, "fixture-song")
        XCTAssertEqual(revealed?.afterMove, true)
        XCTAssertTrue(ended)
    }

    /// A drop on the song's own lane moves nothing: refusing it makes AppKit
    /// slide the image back to the row it came from.
    func testDropThatMovesNothingIsRefusedAndNotLanded() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        var landed = false
        var ended = false
        view.accepts = { $0 == "fixture-song" }
        view.perform = { _, _ in false }
        view.land = { _ in landed = true }
        view.ended = { ended = true }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertFalse(view.performDragOperation(info))
        XCTAssertFalse(landed)
        XCTAssertTrue(ended)
    }

    func testRejectedDragCursorIsPoppedWhenViewLeavesWindow() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        view.accepts = { _ in false }

        XCTAssertEqual(view.draggingUpdated(info), [])
        XCTAssertTrue(view.isShowingNotAllowedCursor)
        // Repeated rejected updates never push twice.
        XCTAssertEqual(view.draggingUpdated(info), [])
        XCTAssertTrue(view.isShowingNotAllowedCursor)

        // SwiftUI recreates the representable / the column collapses mid-drag:
        // AppKit sends no draggingExited, so leaving the window must balance the stack.
        window.contentView = nil
        XCTAssertFalse(view.isShowingNotAllowedCursor)
    }
}

@MainActor
private final class FixtureDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let item: NSDraggingItem
    var enumerationView: NSView?
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(id: String) {
        item = NSDraggingItem(pasteboardWriter: id as NSString)
        super.init()
        draggingPasteboard.setString(id, forType: .string)
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        enumerationView = view
        var stop: ObjCBool = false
        block(item, 0, &stop)
    }
}

private struct FixtureColumnLayout: View {
    let showsCard: Bool
    var body: some View {
        VStack {
            Text("Column")
            if showsCard {
                Text("Fixture card").frame(width: 184, height: 54)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
