import AppCore
import FeatureArchiveBrowser
import SwiftUI
import XCTest

final class FeatureRegistryTests: XCTestCase {
    func testPreservesRegistrationOrder() throws {
        let registry = try ToolRegistry(features: [
            TestFeature(id: "first", shortLabel: "First"),
            TestFeature(id: "second", shortLabel: "Second")
        ])

        XCTAssertEqual(registry.metadata.map(\.id), ["first", "second"])
        XCTAssertEqual(registry.metadata.map(\.shortLabel), ["First", "Second"])
    }

    func testLooksUpFeatureByID() throws {
        let second = TestFeature(id: "second", shortLabel: "Second")
        let registry = try ToolRegistry(features: [
            TestFeature(id: "first", shortLabel: "First"),
            second
        ])

        let found = registry.feature(for: "second")

        XCTAssertEqual(found?.metadata.id, second.metadata.id)
    }

    func testExposesSidebarSection() throws {
        let registry = try ToolRegistry(features: [
            TestFeature(id: "library", shortLabel: "Library", section: .library),
            TestFeature(id: "tool", shortLabel: "Tool")
        ])

        XCTAssertEqual(registry.metadata.map(\.section), [.library, .production])
    }

    func testRejectsDuplicateFeatureIDs() {
        XCTAssertThrowsError(
            try ToolRegistry(features: [
                TestFeature(id: "duplicate", shortLabel: "One"),
                TestFeature(id: "duplicate", shortLabel: "Two")
            ])
        ) { error in
            XCTAssertEqual(error as? DuplicateToolFeatureID, DuplicateToolFeatureID(id: "duplicate"))
        }
    }

    @MainActor
    func testArchiveBrowserRegistersFirst() throws {
        let context = ToolContext.smokeTest()
        let registry = try ToolRegistry(features: [
            ArchiveBrowserFeature(viewModel: ArchiveBrowserViewModel(context: context)),
            TestFeature(id: "wav-converter", shortLabel: "WAV")
        ])
        XCTAssertEqual(registry.metadata.first?.id, "archive-browser")
        XCTAssertEqual(registry.metadata.first?.section, .library)
    }

    func testAddingSecondFeatureDoesNotRequireExistingFeatureChanges() throws {
        let dev = TestFeature(id: "dev-tool", shortLabel: "Dev")
        let second = SecondFeature()

        let registry = try ToolRegistry(features: [dev, second])

        XCTAssertEqual(registry.metadata.map(\.shortLabel), ["Dev", "Second"])
        XCTAssertEqual(registry.feature(for: "second-feature")?.metadata.displayName, "Second Feature")
    }
}

private struct TestFeature: ToolFeature {
    let metadata: ToolMetadata

    init(
        id: ToolFeatureID,
        shortLabel: String,
        section: ToolSection = .production
    ) {
        metadata = ToolMetadata(
            id: id,
            displayName: shortLabel,
            shortLabel: shortLabel,
            systemImage: "hammer",
            section: section
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}

private struct SecondFeature: ToolFeature {
    let metadata = ToolMetadata(
        id: "second-feature",
        displayName: "Second Feature",
        shortLabel: "Second",
        systemImage: "plus"
    )

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
