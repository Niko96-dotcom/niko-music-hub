import AppCore
import SwiftUI
import XCTest

/// The sidebar order comes from each tool's `ToolSection`, not from tool IDs. The
/// app registers the Dev Tool and the design preview after Settings
/// (`AppComposition.make()`), so registration order alone is not the sidebar order.
final class ToolSectionTests: XCTestCase {
    func testSidebarOrderGroupsTheProductionRegistrationBySection() throws {
        let registry = try ToolRegistry(features: [
            SectionStub(id: .archiveBrowser, section: .library),
            SectionStub(id: .bpmTapper),
            SectionStub(id: .wavConverter),
            SectionStub(id: .audioRecorder),
            SectionStub(id: .downloader),
            SectionStub(id: .stemSeparation),
            SectionStub(id: "settings", section: .settings),
            SectionStub(id: "dev-tool"),
            SectionStub(id: "design-system-preview"),
        ])
        let production: [ToolFeatureID] = [
            .bpmTapper, .wavConverter, .audioRecorder, .downloader, .stemSeparation, "dev-tool", "design-system-preview",
        ]

        XCTAssertEqual(
            ToolSection.sidebarOrder(registry.metadata).map(\.id),
            [.archiveBrowser] + production + ["settings"]
        )
        XCTAssertEqual(HubToolsShortcutMap.menuMetadata(from: registry.metadata).map(\.id), [.archiveBrowser] + production + ["settings"])
        XCTAssertEqual(ToolSidebarSelection.arrowKeyOrder(registry.metadata).map(\.id), [.archiveBrowser] + production)
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "dev-tool", in: registry.metadata), Character("7"))
        XCTAssertNil(HubToolsShortcutMap.commandDigit(for: "settings", in: registry.metadata))
        XCTAssertEqual(
            MenuBarMenuModel.dockEntries(registry: registry).map(\.id),
            ["open-app", "archive-browser"] + production.map(\.rawValue) + ["output-inbox"]
        )
    }

    func testSettingsIsNeverTheLaunchToolAndTheLibraryToolIsTheDefault() throws {
        let registry = try ToolRegistry(features: [
            SectionStub(id: .bpmTapper),
            SectionStub(id: "settings", section: .settings),
            SectionStub(id: .archiveBrowser, section: .library),
        ])

        XCTAssertEqual(registry.preferredDefaultFeatureID, .archiveBrowser)
        XCTAssertEqual(registry.resolvedLaunchToolID(storedRaw: "settings", environment: [:]), .archiveBrowser)
        XCTAssertEqual(registry.resolvedLaunchToolID(storedRaw: "bpm-tapper", environment: [:]), .bpmTapper)
    }
}

private struct SectionStub: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, section: ToolSection = .production) {
        metadata = ToolMetadata(
            id: id,
            displayName: id.rawValue,
            shortLabel: id.rawValue,
            systemImage: "hammer",
            section: section
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
