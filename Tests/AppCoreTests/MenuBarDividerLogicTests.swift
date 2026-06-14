import AppCore
import SwiftUI
import XCTest

final class MenuBarDividerLogicTests: XCTestCase {

    // MARK: - Divider absent when no tool rows (MBAR-04 degenerate case)

    func testNoDividerWhenOnlyOutputInboxResolved() throws {
        let registry = try ToolRegistry(features: [])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        // Only output-inbox remains
        let inboxEntry = try XCTUnwrap(entries.first { $0.id == "output-inbox" })
        let showDivider = MenuBarMenuModel.shouldShowDivider(before: inboxEntry, in: entries)
        XCTAssertFalse(showDivider, "Divider must be omitted when no openTool rows precede Output Inbox")
    }

    // MARK: - Divider present when tool rows precede inbox

    func testDividerShownWhenToolRowsPrecedeOutputInbox() throws {
        let registry = try ToolRegistry(features: [StubToolFeature(id: "bpm-tapper")])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let inboxEntry = try XCTUnwrap(entries.first { $0.id == "output-inbox" })
        let showDivider = MenuBarMenuModel.shouldShowDivider(before: inboxEntry, in: entries)
        XCTAssertTrue(showDivider, "Divider must appear when at least one openTool row precedes Output Inbox")
    }

    // MARK: - Divider not triggered by non-inbox entries

    func testNoDividerForOpenToolEntry() throws {
        let registry = try ToolRegistry(features: [StubToolFeature(id: "bpm-tapper")])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let toolEntry = try XCTUnwrap(entries.first { $0.id == "bpm-tapper" })
        let showDivider = MenuBarMenuModel.shouldShowDivider(before: toolEntry, in: entries)
        XCTAssertFalse(showDivider, "Divider must not be placed before a tool row — only before Output Inbox")
    }
}

// MARK: - Stub

private struct StubToolFeature: ToolFeature {
    let metadata: ToolMetadata
    init(id: String) {
        metadata = ToolMetadata(
            id: ToolFeatureID(rawValue: id),
            displayName: id,
            shortLabel: id,
            systemImage: "gearshape",
            capabilities: []
        )
    }
    @MainActor
    func makeView(context: ToolContext) -> AnyView { AnyView(EmptyView()) }
}
