import AppCore
import AppKit
import SwiftUI
import XCTest

/// Stems-latency regression: `ToolOutputShelf` must build rows lazily when hosted
/// like `HubInspectorPage` (ScrollView -> VStack -> shelf -> `HubListSection`), so
/// a long stem run does not construct every far-offscreen row at initial layout,
/// while every row stays reachable via scroll with identical row UI.
///
/// Probes row construction through the `subtitle` callback (invoked from the row
/// body), following the existing `NSHostingView` + borderless-window patterns.
/// Membership-only assertions: no timing thresholds.
@MainActor
final class ToolOutputShelfTests: XCTestCase {
    func testFarOffscreenRowsBuildLazilyAndBecomeAvailableOnScroll() {
        let rowCount = 200
        let items = (0..<rowCount).map { index in
            OutputInboxItem(
                fileURL: URL(fileURLWithPath: "/tmp/ToolOutputShelfTests/row-\(index).wav"),
                sourceToolID: "stem-separation"
            )
        }
        let built = BuiltItemIDs()
        let shelfID = "ToolOutputShelfTests.shelf"
        let proxyBox = ScrollProxyBox()
        let root = ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ToolOutputShelf(
                        title: "Results",
                        items: items,
                        subtitle: { item in
                            built.insert(item.id)
                            return "probe"
                        },
                        onReveal: { _ in }
                    )
                    .id(shelfID)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(width: 640, height: 500)
            .onAppear { proxyBox.proxy = proxy }
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        settle()

        // Harness sanity: the first (visible) row must be built after layout.
        XCTAssertTrue(
            built.contains(items[0].id),
            "Hosted harness must build the visible first row (built \(built.count)/\(rowCount))"
        )
        // Regression: far-offscreen rows must not be built at initial layout.
        XCTAssertFalse(
            built.contains(items[rowCount - 1].id),
            "Far-offscreen rows must stay unbuilt at initial layout (built \(built.count)/\(rowCount))"
        )

        // Every result stays reachable: scrolling to the bottom builds the far row.
        guard let proxy = proxyBox.proxy else {
            XCTFail("Hosted harness must capture the ScrollViewProxy on appear")
            return
        }
        proxy.scrollTo(shelfID, anchor: .bottom)
        settle()
        XCTAssertTrue(
            built.contains(items[rowCount - 1].id),
            "Far rows must become available after scrolling to the bottom"
        )
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    }
}

/// Main-thread-only probe set recording which row bodies were constructed.
private final class BuiltItemIDs: @unchecked Sendable {
    private var ids = Set<UUID>()
    func insert(_ id: UUID) { ids.insert(id) }
    func contains(_ id: UUID) -> Bool { ids.contains(id) }
    var count: Int { ids.count }
}

private final class ScrollProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}
