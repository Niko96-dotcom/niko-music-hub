import AppCore
import SwiftUI
import XCTest

final class ToolRegistryUIToolTests: XCTestCase {
    func testInitialToolIDFromEnvironment() {
        XCTAssertEqual(
            ToolRegistry.initialToolID(from: ["NIKO_MUSIC_HUB_UI_TOOL": "bpm-tapper"])?.rawValue,
            "bpm-tapper"
        )
        XCTAssertNil(ToolRegistry.initialToolID(from: [:]))
        XCTAssertNil(ToolRegistry.initialToolID(from: ["NIKO_MUSIC_HUB_UI_TOOL": "  "]))
    }

    func testResolvedLaunchToolIDPrefersUIToolOverStored() throws {
        let registry = try ToolRegistry(features: [
            StubLaunchFeature(id: "archive-browser"),
            StubLaunchFeature(id: "downloader"),
            StubLaunchFeature(id: "settings"),
        ])

        XCTAssertEqual(
            registry.resolvedLaunchToolID(
                storedRaw: "downloader",
                environment: ["NIKO_MUSIC_HUB_UI_TOOL": "archive-browser"]
            ),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(
            registry.resolvedLaunchToolID(storedRaw: "downloader", environment: [:]),
            ToolFeatureID("downloader")
        )
        XCTAssertEqual(
            registry.resolvedLaunchToolID(storedRaw: "settings", environment: [:]),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(
            registry.resolvedLaunchToolID(storedRaw: "missing-tool", environment: [:]),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(
            registry.resolvedLaunchToolID(storedRaw: nil, environment: [:]),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(
            registry.resolvedLaunchToolID(
                storedRaw: "downloader",
                environment: ["NIKO_MUSIC_HUB_UI_TOOL": "settings"]
            ),
            ToolFeatureID("archive-browser")
        )
    }
}

private struct StubLaunchFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID) {
        metadata = ToolMetadata(
            id: id,
            displayName: id.rawValue,
            shortLabel: id.rawValue,
            systemImage: "hammer"
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
