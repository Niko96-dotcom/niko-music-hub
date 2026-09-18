import AppCore
import SwiftUI
import XCTest

final class ToolSidebarSelectionTests: XCTestCase {
    func testSelectedToolSpeaksSelectedNotShortLabel() {
        XCTAssertEqual(ToolSidebarSelection.accessibilityValue(isSelected: true), "Selected")
        XCTAssertEqual(ToolSidebarSelection.accessibilityValue(isSelected: false), "")
        XCTAssertEqual(ToolSidebarSelection.accessibilityTraits(isSelected: true), .isSelected)
        XCTAssertEqual(ToolSidebarSelection.accessibilityTraits(isSelected: false), [])
    }

    func testArrowDownCyclesRegistryMetadataAndSkipsHelperTools() throws {
        let registry = try ToolRegistry(features: [
            StubSidebarFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubSidebarFeature(id: "bpm-tapper", displayName: "BPM Tapper"),
            StubSidebarFeature(id: "settings", displayName: "Settings"),
        ])

        XCTAssertFalse(registry.metadata.contains { $0.displayName == "Helper Tools" })

        XCTAssertEqual(
            ToolSidebarSelection.move(
                direction: .down,
                metadata: registry.metadata,
                selectedID: ToolFeatureID("archive-browser")
            ),
            ToolFeatureID("bpm-tapper")
        )
        XCTAssertEqual(
            ToolSidebarSelection.move(
                direction: .down,
                metadata: registry.metadata,
                selectedID: ToolFeatureID("settings")
            ),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(
            ToolSidebarSelection.move(
                direction: .up,
                metadata: registry.metadata,
                selectedID: ToolFeatureID("archive-browser")
            ),
            ToolFeatureID("settings")
        )
        XCTAssertEqual(
            ToolSidebarSelection.move(
                direction: .down,
                metadata: registry.metadata,
                selectedID: nil
            ),
            ToolFeatureID("archive-browser")
        )
    }

    func testSidebarWiresSelectionTraitsHintAndMoveCommand() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/ToolSidebarView.swift")

        XCTAssertTrue(source.contains("ToolSidebarSelection.accessibilityValue(isSelected:"))
        XCTAssertTrue(source.contains("ToolSidebarSelection.accessibilityTraits(isSelected:"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits("))
        XCTAssertFalse(source.contains(".accessibilityValue(metadata.shortLabel)"))
        XCTAssertTrue(source.contains(".onMoveCommand"))
        XCTAssertTrue(source.contains("ToolSidebarSelection.move("))
        XCTAssertTrue(source.contains("registry.metadata"))
        XCTAssertFalse(source.contains("List(selection:"))

        XCTAssertTrue(source.contains("accessibilityLabel(\"Helper tools status\")"))
        XCTAssertTrue(
            source.contains(
                "accessibilityHint(\"Shows whether yt-dlp, FFmpeg, and demucs-mlx are ready.\")"
            )
        )
        XCTAssertTrue(source.contains("sidebarCaption(\"Status\")"))

        let helperBlock = helperHealthRowSource(source)
        XCTAssertFalse(
            helperBlock.contains("accessibilityAddTraits"),
            "Helper Tools must not receive .isSelected"
        )
        XCTAssertFalse(helperBlock.contains("hubSidebarNavRow"))
    }

    private func helperHealthRowSource(_ source: String) -> String {
        guard let start = source.range(of: "private var helperHealthRow: some View") else {
            return ""
        }
        return String(source[start.lowerBound...])
    }
}

private struct StubSidebarFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, displayName: String) {
        metadata = ToolMetadata(
            id: id,
            displayName: displayName,
            shortLabel: displayName,
            systemImage: "hammer"
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
