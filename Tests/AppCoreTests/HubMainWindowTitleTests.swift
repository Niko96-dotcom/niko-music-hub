import AppCore
import SwiftUI
import XCTest

final class HubMainWindowTitleTests: XCTestCase {
    func testMainWindowTitleUsesToolDisplayNameOrAppFallback() throws {
        let registry = try ToolRegistry(features: [
            StubChromeFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubChromeFeature(id: "downloader", displayName: "Downloader"),
        ])

        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("archive-browser"), registry: registry),
            "Archive Browser"
        )
        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("downloader"), registry: registry),
            "Downloader"
        )
        XCTAssertEqual(HubMainWindowTitle.resolved(selectedToolID: nil, registry: registry), "Niko Music Hub")
        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("missing-tool"), registry: registry),
            "Niko Music Hub"
        )
        // Clears the repositioned lights (zoom ends ~85) + 14pt gap.
        XCTAssertEqual(HubShellLayout.titleBarLeadingInset, 99)
        XCTAssertEqual(HubShellLayout.trafficAxisX, 31)
    }
}

private struct StubChromeFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, displayName: String) {
        metadata = ToolMetadata(
            id: id,
            displayName: displayName,
            shortLabel: displayName,
            systemImage: "hammer",
            section: .declared(by: id)
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
