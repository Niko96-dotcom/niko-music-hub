@testable import AppCore
import AppKit
import XCTest

@MainActor
final class HubSheetTerminationTests: XCTestCase {
    func testSheetAttachmentAllowsQuitWithoutChangingItsFrame() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.preventsApplicationTerminationWhenModal = true
        let originalFrame = window.frame
        let bridge = HubSheetTerminationView()

        window.contentView?.addSubview(bridge)

        XCTAssertFalse(window.preventsApplicationTerminationWhenModal)
        XCTAssertEqual(window.frame, originalFrame)
    }
}
