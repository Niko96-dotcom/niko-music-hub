import AppCore
import SwiftUI
import XCTest

/// Unit coverage for QA-03: routing smoke assertions on production AppCore types.
/// Mirrors what QuickAccessRoutingSmoke.run() asserts in the e2e smoke binary.
@MainActor
final class QuickAccessRoutingSmokeTests: XCTestCase {

    // MARK: - Registry resolution

    func testWAVConverterResolvesInStubRegistry() throws {
        let registry = try ToolRegistry(features: [StubToolFeature(id: "wav-converter")])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let hasWavConverter = entries.contains { entry in
            if case .openTool(let id) = entry.command { return id.rawValue == "wav-converter" }
            return false
        }
        XCTAssertTrue(hasWavConverter, "wav-converter must resolve against a registry containing a wav-converter StubToolFeature")
    }

    func testOutputInboxAlwaysResolvesWithEmptyRegistry() throws {
        let registry = try ToolRegistry(features: [])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let hasOutputInbox = entries.contains { entry in
            if case .revealOutputInbox = entry.command { return true }
            return false
        }
        XCTAssertTrue(hasOutputInbox, "Output Inbox always resolves regardless of registry (MBAR-04)")
    }

    // MARK: - Router command execution

    func testOpenToolPublishesRequest() throws {
        let router = QuickAccessRouter()
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.requestedToolID?.rawValue, "wav-converter")
    }

    func testRevealOutputInboxSetsFlag() throws {
        let router = QuickAccessRouter()
        router.execute(.revealOutputInbox)
        XCTAssertTrue(router.revealOutputInbox)
    }

    func testBothCommandsSequential() throws {
        let router = QuickAccessRouter()
        router.execute(.openTool("wav-converter"))
        router.execute(.revealOutputInbox)
        XCTAssertEqual(router.requestedToolID?.rawValue, "wav-converter")
        XCTAssertTrue(router.revealOutputInbox)
    }
}

// MARK: - Stub

private struct StubToolFeature: ToolFeature {
    let metadata: ToolMetadata
    init(id: String) {
        metadata = ToolMetadata(
            id: ToolFeatureID(id),
            displayName: id,
            shortLabel: id,
            systemImage: "gearshape",
            capabilities: []
        )
    }
    @MainActor
    func makeView(context: ToolContext) -> AnyView { AnyView(EmptyView()) }
}
