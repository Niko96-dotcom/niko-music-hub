import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Regression for scan-hang on the open plugins section: `applyCatalogScanUpdate`
/// invalidates CPR summaries by canceling the shared `cprPlugins` task for ANY
/// changed CPR, which also cancels a pending selected load. Without a restart,
/// an expanded section stays on "Loading plugin list..." with a nil summary.
/// Fixture tests only (temp folders + real marker CPR files); no network,
/// release, or real music.
@MainActor
final class ArchivePluginScanRefreshTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugin-scan-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeCPR(named name: String, folder: URL, plugins: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data("header NIKO_PLUGINS: \(plugins)\nfooter".utf8).write(to: url, options: .atomic)
        return url
    }

    private func waitForPlugins(
        _ viewModel: ArchiveBrowserViewModel,
        timeout: TimeInterval = 5
    ) async -> CPRPluginSummary? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let selected = viewModel.selectedSong,
               let summary = viewModel.cprPluginSummary(for: selected) {
                return summary
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if let selected = viewModel.selectedSong {
            return viewModel.cprPluginSummary(for: selected)
        }
        return nil
    }

    func testOpenPluginsPopulatesAfterUnrelatedCPRChange() async throws {
        CPRPluginSummaryService.clearCache()
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selectedFolder = root.appendingPathComponent("Selected Song", isDirectory: true)
        let unrelatedFolder = root.appendingPathComponent("Unrelated Song", isDirectory: true)
        let selectedCPRURL = try makeCPR(named: "Selected.cpr", folder: selectedFolder, plugins: "Comp, EQ")
        let unrelatedCPRURL = try makeCPR(named: "Unrelated.cpr", folder: unrelatedFolder, plugins: "Other")

        let selectedVersion = ProjectVersion(
            filePath: selectedCPRURL,
            fileName: selectedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let unrelatedV1 = ProjectVersion(
            filePath: unrelatedCPRURL,
            fileName: unrelatedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let selected = Song(
            folderPath: selectedFolder, originalFolderName: "Selected Song", displayTitle: "Selected Song",
            projectVersions: [selectedVersion], latestCPR: selectedVersion
        )
        let unrelated = Song(
            folderPath: unrelatedFolder, originalFolderName: "Unrelated Song", displayTitle: "Unrelated Song",
            projectVersions: [unrelatedV1], latestCPR: unrelatedV1
        )

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.scannedSongs = [selected, unrelated]
        viewModel.songs = [selected, unrelated]
        viewModel.selectedSong = selected
        viewModel.pluginsSectionExpanded = true

        // Start the selected load, then synchronously apply a catalog update
        // where only the UNRELATED song's CPR changed. The shared cancel in
        // the unrelated invalidation kills the pending selected task; the
        // fixed scan host must restart the selected summary.
        viewModel.refreshCPRPluginSummary(for: selected)

        let unrelatedV2 = ProjectVersion(
            filePath: unrelatedCPRURL,
            fileName: unrelatedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let updatedUnrelated = Song(
            folderPath: unrelatedFolder, originalFolderName: "Unrelated Song", displayTitle: "Unrelated Song",
            projectVersions: [unrelatedV2], latestCPR: unrelatedV2
        )
        let update = viewModel.catalog.applyFullScanResult(
            result: ScanResult(songs: [selected, updatedUnrelated], globalWarnings: [], skippedEntries: []),
            roots: [],
            collaborators: [],
            scannedAt: Date()
        )
        viewModel.applyCatalogScanUpdate(update, roots: [])

        // Section stays open and selection survives the rescan.
        XCTAssertTrue(viewModel.pluginsSectionExpanded)
        XCTAssertEqual(viewModel.selectedSong?.id, selected.id)

        let summary = await waitForPlugins(viewModel)
        let populated = try XCTUnwrap(summary, "open plugins section never populated after catalog update")
        XCTAssertEqual(Set(populated.pluginNames), ["Comp", "EQ"])
    }

    func testCachedSelectedSummarySurvivesUnrelatedCPRChange() async throws {
        CPRPluginSummaryService.clearCache()
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selectedFolder = root.appendingPathComponent("Selected Song", isDirectory: true)
        let unrelatedFolder = root.appendingPathComponent("Unrelated Song", isDirectory: true)
        let selectedCPRURL = try makeCPR(named: "Selected.cpr", folder: selectedFolder, plugins: "Comp, EQ")
        let unrelatedCPRURL = try makeCPR(named: "Unrelated.cpr", folder: unrelatedFolder, plugins: "Other")

        let selectedVersion = ProjectVersion(
            filePath: selectedCPRURL,
            fileName: selectedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let unrelatedV1 = ProjectVersion(
            filePath: unrelatedCPRURL,
            fileName: unrelatedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let selected = Song(
            folderPath: selectedFolder, originalFolderName: "Selected Song", displayTitle: "Selected Song",
            projectVersions: [selectedVersion], latestCPR: selectedVersion
        )
        let unrelated = Song(
            folderPath: unrelatedFolder, originalFolderName: "Unrelated Song", displayTitle: "Unrelated Song",
            projectVersions: [unrelatedV1], latestCPR: unrelatedV1
        )

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.scannedSongs = [selected, unrelated]
        viewModel.songs = [selected, unrelated]
        viewModel.selectedSong = selected
        viewModel.pluginsSectionExpanded = true
        viewModel.refreshCPRPluginSummary(for: selected)
        let first = await waitForPlugins(viewModel)
        XCTAssertNotNil(first)

        // An unrelated CPR change must preserve the cached selected summary:
        // no nil gap, no per-keystroke reload when the cache already hits.
        let unrelatedV2 = ProjectVersion(
            filePath: unrelatedCPRURL,
            fileName: unrelatedCPRURL.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let updatedUnrelated = Song(
            folderPath: unrelatedFolder, originalFolderName: "Unrelated Song", displayTitle: "Unrelated Song",
            projectVersions: [unrelatedV2], latestCPR: unrelatedV2
        )
        let update = viewModel.catalog.applyFullScanResult(
            result: ScanResult(songs: [selected, updatedUnrelated], globalWarnings: [], skippedEntries: []),
            roots: [],
            collaborators: [],
            scannedAt: Date()
        )
        viewModel.applyCatalogScanUpdate(update, roots: [])

        XCTAssertTrue(viewModel.pluginsSectionExpanded)
        let cached = viewModel.selectedSong.flatMap { viewModel.cprPluginSummary(for: $0) }
        XCTAssertNotNil(cached)
        XCTAssertEqual(Set(cached?.pluginNames ?? []), ["Comp", "EQ"])
    }
}
