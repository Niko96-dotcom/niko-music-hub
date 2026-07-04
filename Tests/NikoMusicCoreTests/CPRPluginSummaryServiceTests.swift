import XCTest
@testable import NikoMusicCore

final class CPRPluginSummaryServiceTests: XCTestCase {
    func testParsesEmbeddedMarkerFromFixtureCPR() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugins-\(UUID().uuidString).cpr")
        let contents = "binary\u{0}NIKO_PLUGINS:EQ One,Compressor Pro\u{0}trailer"
        FileManager.default.createFile(atPath: file.path, contents: Data(contents.utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertEqual(summary.pluginNames, ["Compressor Pro", "EQ One"])
        XCTAssertEqual(summary.source, "marker")
    }

    func testReturnsEmptyWhenNoPluginsFound() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).cpr")
        FileManager.default.createFile(atPath: file.path, contents: Data("fixture".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertTrue(summary.pluginNames.isEmpty)
        XCTAssertEqual(summary.source, "empty")
    }
}
