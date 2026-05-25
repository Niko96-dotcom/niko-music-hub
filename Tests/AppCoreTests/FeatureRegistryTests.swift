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

    func testExposesCapabilityFlags() throws {
        let registry = try ToolRegistry(features: [
            TestFeature(id: "files", shortLabel: "Files", capabilities: [.producesFiles, .runsJobs])
        ])

        XCTAssertTrue(registry.metadata[0].capabilities.contains(.producesFiles))
        XCTAssertTrue(registry.metadata[0].capabilities.contains(.runsJobs))
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

    func testArchiveBrowserRegistersFirst() throws {
        let registry = try ToolRegistry(features: [
            ArchiveBrowserFeature(),
            TestFeature(id: "wav-converter", shortLabel: "WAV")
        ])
        XCTAssertEqual(registry.metadata.first?.id, "archive-browser")
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
        capabilities: ToolCapability = []
    ) {
        metadata = ToolMetadata(
            id: id,
            displayName: shortLabel,
            shortLabel: shortLabel,
            systemImage: "hammer",
            capabilities: capabilities
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
