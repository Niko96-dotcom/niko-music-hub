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

    func testUILaunchToolAppliesBeforeCompositionResolvesSelection() throws {
        let app = try String(
            contentsOfFile: "Sources/NikoMusicHub/NikoMusicHubApp.swift",
            encoding: .utf8
        )
        let tool = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/UILaunchTool.swift",
            encoding: .utf8
        )

        // The `-ui-tool` bridge must run before the composition resolves the
        // launch selection once in `NikoMusicHubApp.init`; anything later never
        // takes effect (the shell only reads `selectedToolID` afterwards).
        let apply = try XCTUnwrap(app.range(of: "UILaunchTool.applyFromLaunchArguments()"))
        let make = try XCTUnwrap(app.range(of: "AppComposition.make()"))
        XCTAssertLessThan(
            apply.lowerBound,
            make.lowerBound,
            "UILaunchTool must apply -ui-tool before AppComposition.make() resolves selection"
        )

        // The late redundant mutation in `applicationWillFinishLaunching` is gone.
        let delegateStart = try XCTUnwrap(app.range(of: "func applicationWillFinishLaunching"))
        let delegateTail = String(app[delegateStart.lowerBound...])
        let delegateEnd = delegateTail.range(of: "\n    func ")?.lowerBound ?? delegateTail.endIndex
        XCTAssertFalse(
            String(delegateTail[..<delegateEnd]).contains("UILaunchTool"),
            "applicationWillFinishLaunching must not re-apply -ui-tool after composition"
        )

        // The bridge still maps `-ui-tool <id>` onto the environment seam the
        // registry resolution reads (`ToolRegistry.initialToolID`).
        XCTAssertTrue(tool.contains("firstIndex(of: \"-ui-tool\")"))
        XCTAssertTrue(tool.contains("setenv(\"NIKO_MUSIC_HUB_UI_TOOL\""))
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
