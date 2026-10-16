import XCTest
@testable import NikoMusicCore

final class CPRPluginSummaryServiceTests: XCTestCase {
    func testParsesEmbeddedMarkerFromFixtureCPR() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugins-\(UUID().uuidString).cpr")
        let contents = "binary\u{0}NIKO_PLUGINS:EQ One,Compressor Pro\u{0}trailer"
        FileManager.default.createFile(atPath: file.path, contents: Data(contents.utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = await CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertEqual(summary.pluginNames, ["Compressor Pro", "EQ One"])
        XCTAssertEqual(summary.source, "marker")
    }

    func testReturnsEmptyWhenNoPluginsFound() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).cpr")
        FileManager.default.createFile(atPath: file.path, contents: Data("fixture".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = await CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertTrue(summary.pluginNames.isEmpty)
        XCTAssertEqual(summary.source, "empty")
    }

    func testSkipsInMemoryParserForOversizedCPR() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-\(UUID().uuidString).cpr")
        defer { try? FileManager.default.removeItem(at: file) }

        var data = Data(repeating: 0, count: 9 * 1024 * 1024)
        data.append(Data("Name=\"Huge Synth\"".utf8))
        try data.write(to: file)

        let summary = await CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertTrue(summary.pluginNames.isEmpty)
        XCTAssertEqual(summary.source, "empty")
    }

    func testParsesSubprocessOutputWithoutCommentsOrBlankLines() {
        XCTAssertEqual(
            CPRPluginSummaryService.parsePluginListOutput("# generated\nEQ One\n\nCompressor Pro\n"),
            ["EQ One", "Compressor Pro"]
        )
    }

    func testCancellationStopsSubprocessPathAndDoesNotCacheEmptyFallback() async throws {
        CPRPluginSummaryService.clearCache()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugins-cancel-\(UUID().uuidString).cpr")
        let contents = "binary\u{0}NIKO_PLUGINS:Marker Synth\u{0}trailer"
        FileManager.default.createFile(atPath: file.path, contents: Data(contents.utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let probe = PluginSubprocessProbe()

        let task = Task {
            await CPRPluginSummaryService.loadPlugins(
                cprURL: file,
                subprocessRunner: { _ in await probe.run() }
            )
        }
        for _ in 0..<100 where await !probe.started {
            try await Task.sleep(for: .milliseconds(10))
        }
        let didStart = await probe.started
        XCTAssertTrue(didStart)
        task.cancel()
        let canceledSummary = await task.value
        let didCancel = await probe.canceled

        XCTAssertTrue(canceledSummary.pluginNames.isEmpty)
        XCTAssertTrue(didCancel)

        let uncanceledSummary = await CPRPluginSummaryService.loadPlugins(
            cprURL: file,
            subprocessRunner: { _ in nil }
        )
        XCTAssertEqual(uncanceledSummary.pluginNames, ["Marker Synth"])
        XCTAssertEqual(uncanceledSummary.source, "marker")
    }

    func testFullCacheKeepsJustInsertedOldProject() async throws {
        CPRPluginSummaryService.clearCache()
        defer { CPRPluginSummaryService.clearCache() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugins-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<128 {
            let file = directory.appendingPathComponent("recent-\(index).cpr")
            FileManager.default.createFile(atPath: file.path, contents: Data("fixture".utf8))
            _ = await CPRPluginSummaryService.loadPlugins(cprURL: file, subprocessRunner: { _ in ["Synth"] })
        }

        let oldFile = directory.appendingPathComponent("old.cpr")
        FileManager.default.createFile(atPath: oldFile.path, contents: Data("fixture".utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 946_684_800)],
            ofItemAtPath: oldFile.path
        )
        let calls = PluginSubprocessCallCounter()
        _ = await CPRPluginSummaryService.loadPlugins(
            cprURL: oldFile,
            subprocessRunner: { _ in await calls.record() }
        )
        let summary = await CPRPluginSummaryService.loadPlugins(
            cprURL: oldFile,
            subprocessRunner: { _ in await calls.record() }
        )

        let callCount = await calls.count
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(summary.pluginNames, ["Old Synth"])
    }
}

private actor PluginSubprocessCallCounter {
    private(set) var count = 0

    func record() -> [String]? {
        count += 1
        return ["Old Synth"]
    }
}

private actor PluginSubprocessProbe {
    private(set) var started = false
    private(set) var canceled = false

    func run() async -> [String]? {
        started = true
        do {
            try await Task.sleep(for: .seconds(10))
            return ["Should Not Complete"]
        } catch is CancellationError {
            canceled = true
            return nil
        } catch {
            return nil
        }
    }
}
