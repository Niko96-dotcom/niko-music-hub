import AppKit
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveBoardDropHostTests: XCTestCase {
    func testNewCardLayoutIsAvailableBeforeDropReturns() {
        let layout = ArchiveBoardDropLayout()
        let view = ArchiveBoardDropHostingView(rootView: FixtureColumnLayout(showsCard: false, layout: layout))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        view.accepts = { $0 == "fixture-song" }
        view.refreshedContent = { FixtureColumnLayout(showsCard: true, layout: layout) }
        view.landingFrame = { layout.frames[$0] }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertNotNil(layout.frames["fixture-song"])
        XCTAssertEqual(info.item.draggingFrame, layout.frames["fixture-song"])
        XCTAssertGreaterThan(info.item.draggingFrame.height, 0)
    }

    func testDropValidatesAgainBeforeMutationAndRespectsReducedMotion() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        var valid = true
        var mutations = 0
        view.accepts = { valid && $0 == "fixture-song" }
        view.perform = { _ in mutations += 1 }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(info.animatesToDestination)
        view.reduceMotion = true
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertFalse(info.animatesToDestination)
        valid = false
        XCTAssertFalse(view.performDragOperation(info))
        XCTAssertEqual(mutations, 0)
    }

    func testAcceptedDropSetsNativeLandingFrameAfterMutation() {
        let view = ArchiveBoardDropHostingView(rootView: Text("Fixture"))
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 600)
        let info = FixtureDraggingInfo(id: "fixture-song")
        defer { info.draggingPasteboard.releaseGlobally() }
        let frame = CGRect(x: 8, y: 40, width: 184, height: 54)
        var moved = false
        var ended = false
        view.accepts = { $0 == "fixture-song" }
        view.perform = { _ in moved = true }
        view.landingFrame = { _ in moved ? frame : nil }
        view.ended = { ended = true }
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertTrue(moved)
        XCTAssertTrue(ended)
        XCTAssertEqual(info.item.draggingFrame, frame)
        XCTAssertTrue(info.enumerationView === view)
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
    let layout: ArchiveBoardDropLayout
    var body: some View {
        VStack {
            Text("Column")
            if showsCard {
                Text("Fixture card").frame(width: 184, height: 54)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ArchiveBoardCardFramesKey.self,
                                value: ["fixture-song": proxy.frame(in: .named("fixture-column"))])
                        }
                    }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "fixture-column")
        .onPreferenceChange(ArchiveBoardCardFramesKey.self) { layout.frames = $0 }
    }
}
