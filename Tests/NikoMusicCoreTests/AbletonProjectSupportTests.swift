import Foundation
import XCTest
import zlib
@testable import NikoMusicCore

final class AbletonProjectSupportTests: XCTestCase {
    func testMixedAndIndependentSongFoldersKeepTheirIdentityAndMetadata() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        try fixture.write("Together/Arrangement v3.cpr", date: 100)
        try fixture.write("Together/Live Project/Arrangement v4.ALS", date: 200)
        try fixture.write("Separate/Arrangement v9.als", date: 300)
        try fixture.write("Together/Live Project/Backup/Arrangement v99.als", date: 900)
        try fixture.write("Together/Live Project/Ableton Project Info/Ignore.als", date: 900)
        try fixture.write("Together/Arrangement.bak.cpr", date: 900)
        try fixture.write("Together/Arrangement.bak.als", date: 900)
        let before = try VaultManifestBuilder().build(at: fixture.root)
        let songs = try MusicArchiveScanner().scan(roots: [fixture.root]).songs
        XCTAssertEqual(songs.count, 2)
        let mixed = try XCTUnwrap(songs.first { $0.originalFolderName == "Together" })
        let separate = try XCTUnwrap(songs.first { $0.originalFolderName == "Separate" })
        XCTAssertEqual(mixed.projectVersions.count, 2)
        XCTAssertEqual(mixed.projectFormats, [.cubase, .abletonLive])
        XCTAssertEqual(mixed.effectiveLatestProject?.fileName, "Arrangement v4.ALS")
        XCTAssertEqual(mixed.effectiveLatestProject?.detectedVersionNumber, 4)
        XCTAssertEqual(mixed.openProjectLabel, "Open in Ableton Live")
        XCTAssertEqual(separate.projectVersions.count, 1)
        XCTAssertNotEqual(mixed.id, separate.id)
        XCTAssertTrue(songs.allSatisfy { $0.scanWarnings.isEmpty })
        let restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(mixed))
        XCTAssertEqual(restored, mixed)
        XCTAssertEqual(restored.projectFormats, [.cubase, .abletonLive])
        try VaultManifestBuilder().verify(before, at: fixture.root)
    }

    func testLooseLiveSetsGroupByTitleAndResolveIncrementalDeletion() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        let first = try fixture.write("First Song v1.als", date: 100)
        let last = try fixture.write("First Song v2.als", date: 200)
        try fixture.write("Second Song.als", date: 300)
        let scanner = MusicArchiveScanner()
        let scan = try scanner.scan(roots: [fixture.root])
        XCTAssertEqual(scan.songs.count, 2)
        XCTAssertTrue(scan.skippedEntries.isEmpty)
        XCTAssertEqual(scan.songs.first { $0.displayTitle == "First Song" }?.projectVersions.count, 2)
        try FileManager.default.removeItem(at: last)
        let resolution = ArchiveSongFolderResolver.resolve(changedPaths: [last], roots: [fixture.root])
        XCTAssertEqual(resolution.rootsForRootLevelScan, [fixture.root])
        let incremental = try scanner.scanIncremental(resolution: resolution, roots: [fixture.root])
        XCTAssertEqual(incremental.songs.first { $0.displayTitle == "First Song" }?.latestCPR?.filePath.resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
    }

    func testManualMainOpensEitherDAWAndAllHiddenVersionsStayClosed() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        let cubase = try fixture.write("Together/Song.cpr", date: 100)
        let ableton = try fixture.write("Together/Song.als", date: 200)
        var song = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.root]).songs.first)
        let opener = MusicItemOpener()
        XCTAssertEqual(try opener.openLatestCPR(for: song, dryRun: true, allowedRoots: [fixture.root])?.path, ableton.path)
        song.cprSelectionMode = .manual
        song.manualMainCPRID = song.projectVersions.first { $0.format == .cubase }?.id
        XCTAssertEqual(song.openProjectLabel, "Open in Cubase")
        XCTAssertEqual(try opener.openLatestCPR(for: song, dryRun: true, allowedRoots: [fixture.root])?.path, cubase.path)
        song.ignoredCPRVersionIDs = song.projectVersions.map(\.id)
        XCTAssertNil(try opener.openLatestCPR(for: song, dryRun: true, allowedRoots: [fixture.root]))
    }

    func testSetSymlinksCannotEscapeSongOrArchiveRoots() throws {
        let fixture = try ProjectFixture()
        let outside = try ProjectFixture()
        defer { fixture.remove(); outside.remove() }
        let external = try outside.write("Outside.als", date: 100)
        let link = fixture.root.appendingPathComponent("Escape.als")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertTrue(try ProjectVersionDetector().detectVersions(in: fixture.root).isEmpty)
        XCTAssertTrue(try MusicArchiveScanner().scan(roots: [fixture.root]).songs.isEmpty)
    }

    func testAbletonTemplateCopiesAllAssetsAndDetectsLiveSet() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        try fixture.write("Template/Starting Point.als", date: 100)
        try fixture.write("Template/Samples/Collected/take.wav", date: 100)
        try fixture.write("Template/Ableton Project Info/Project.cfg", date: 100)
        let template = fixture.root.appendingPathComponent("Template")
        let manifest = try VaultManifestBuilder().build(at: template)
        let song = try NewSongFolderCreator.create(request: NewSongRequest(
            name: "New Song", root: fixture.root.appendingPathComponent("Drafts"), templateFolder: template
        ))
        XCTAssertEqual(song.projectFormats, [.abletonLive])
        XCTAssertEqual(song.effectiveLatestProject?.fileName, "Starting Point.als")
        XCTAssertEqual(try Data(contentsOf: song.folderPath.appendingPathComponent("Samples/Collected/take.wav")), Data("fixture".utf8))
        try VaultManifestBuilder().verify(manifest, at: template)
    }

    func testExportsOutrankCollectedAndRecordedSamples() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        try fixture.write("Song/Session.als", date: 100)
        try fixture.write("Song/Live Project/Exports/Song mix.wav", date: 100)
        try fixture.write("Song/Live Project/Samples/Imported/Song master.wav", date: 200)
        try fixture.write("Song/Live Project/Samples/Recorded/Take.wav", date: 200)
        let song = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.root]).songs.first)
        XCTAssertEqual(song.mainPreviewURL?.lastPathComponent, "Song mix.wav")
        XCTAssertTrue(song.previewCandidates.filter { $0.filePath.path.contains("/Samples/") }.allSatisfy { $0.folderRole == .samples })
        XCTAssertFalse(song.hasStems)
    }

    func testAbletonRunningDetectionRequiresDAWBundleExecutable() {
        XCTAssertTrue(AbletonProcessDetector.containsAbleton(inProcessList:
            "/Applications/Ableton Live 12 Suite.app/Contents/MacOS/Live\n/usr/bin/other"))
        XCTAssertTrue(AbletonProcessDetector.containsAbleton(inProcessList:
            "/Volumes/Apps/Ableton Live 11 Intro.app/Contents/MacOS/Live"))
        XCTAssertFalse(AbletonProcessDetector.containsAbleton(inProcessList:
            "/tmp/Live\n/usr/bin/livereload\n/Applications/Ableton Live 12 Suite.app/Contents/MacOS/Helper"))
    }

    func testPluginSummaryReadsGzipVSTVST3AndAUWithoutCubaseSubprocess() async throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("Plugins.als")
        try fixture.writeGzip(Self.pluginXML, to: url)
        let summary = await CPRPluginSummaryService.loadPlugins(cprURL: url, subprocessRunner: { _ in
            XCTFail("Ableton must not use the Cubase subprocess")
            return ["Wrong plugin"]
        })
        XCTAssertEqual(summary.source, "ableton-xml")
        XCTAssertEqual(summary.pluginNames, ["Analog Lab", "Echo & Space", "Vintage Verb"])
    }

    func testPluginSummaryRejectsTruncatedMalformedAndOversizedSets() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("Damaged.als")
        try fixture.writeGzip(Self.pluginXML, to: url)
        XCTAssertNil(AbletonPluginSummaryReader.pluginNames(at: url, maximumBytes: 20))
        var compressed = try Data(contentsOf: url)
        compressed.removeLast(8)
        try compressed.write(to: url)
        XCTAssertNil(AbletonPluginSummaryReader.pluginNames(at: url))
        try fixture.writeGzip("<Ableton><LiveSet>", to: url)
        XCTAssertNil(AbletonPluginSummaryReader.pluginNames(at: url))
        try fixture.writeGzip("<!DOCTYPE Ableton [<!ENTITY a 'unsafe'>]><Ableton/>", to: url)
        XCTAssertNil(AbletonPluginSummaryReader.pluginNames(at: url))
    }

    func testWorkspaceRefusalIsReportedInsteadOfSuccessfulOpen() throws {
        let fixture = try ProjectFixture()
        defer { fixture.remove() }
        let url = try fixture.write("Song/Session.als", date: 100)
        let song = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.root]).songs.first)
        XCTAssertThrowsError(try MusicItemOpener(workspace: RefusingWorkspace()).openLatestCPR(
            for: song, dryRun: false, allowedRoots: [fixture.root]
        )) { error in
            XCTAssertEqual(error as? MusicItemOpenerError, .applicationOpenFailed(url))
        }
    }

    private static let pluginXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Ableton><LiveSet><Tracks><MidiTrack><Name Value="Not a plugin"/>
    <DeviceChain><Devices>
    <PluginDevice><PluginDesc><VstPluginInfo><PlugName Value="Analog Lab"/></VstPluginInfo></PluginDesc></PluginDevice>
    <PluginDevice><PluginDesc><Vst3PluginInfo><Name Value="Echo &amp; Space"/></Vst3PluginInfo></PluginDesc></PluginDevice>
    <PluginDevice><PluginDesc><AuPluginInfo><Name Value="Vintage Verb"/></AuPluginInfo></PluginDesc></PluginDevice>
    </Devices></DeviceChain></MidiTrack></Tracks></LiveSet></Ableton>
    """
}

private struct RefusingWorkspace: WorkspaceOpening {
    func open(_ url: URL) -> Bool { false }
    func revealInFinder(_ url: URL) {}
}

private struct ProjectFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nmh-ableton-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    @discardableResult
    func write(_ relativePath: String, date: TimeInterval) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: date)], ofItemAtPath: url.path)
        return url
    }
    func writeGzip(_ text: String, to url: URL) throws {
        let file = try XCTUnwrap(gzopen(url.path, "wb"))
        let data = Data(text.utf8)
        let written = data.withUnsafeBytes { gzwrite(file, $0.baseAddress, UInt32($0.count)) }
        XCTAssertEqual(Int(written), data.count)
        XCTAssertEqual(gzclose(file), Z_OK)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
