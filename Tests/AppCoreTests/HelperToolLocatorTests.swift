import AppCore
import Foundation
import XCTest

final class HelperToolLocatorTests: XCTestCase {
    func testConfiguredExecutableWins() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let bin = managedRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let managedYtDlp = bin.appendingPathComponent("yt-dlp", isDirectory: false)
        try makeExecutable(at: managedYtDlp)

        let custom = root.appendingPathComponent("custom-yt-dlp", isDirectory: false)
        try makeExecutable(at: custom)

        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let settings = HelperToolSettings(ytDlp: custom)

        XCTAssertEqual(locator.resolve(.ytDlp, settings: settings)?.path, custom.path)
    }

    func testConfiguredButMissingFallsBackToManaged() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let bin = managedRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let managedFfmpeg = bin.appendingPathComponent("ffmpeg", isDirectory: false)
        try makeExecutable(at: managedFfmpeg)

        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let settings = HelperToolSettings(
            ffmpeg: root.appendingPathComponent("missing-ffmpeg", isDirectory: false)
        )

        XCTAssertEqual(locator.resolve(.ffmpeg, settings: settings)?.path, managedFfmpeg.path)
    }

    func testManagedWinsOverSystemDirectory() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let bin = managedRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let managedFfmpeg = bin.appendingPathComponent("ffmpeg", isDirectory: false)
        try makeExecutable(at: managedFfmpeg)

        let systemDir = root.appendingPathComponent("system-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)
        try makeExecutable(at: systemDir.appendingPathComponent("ffmpeg", isDirectory: false))

        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [systemDir])
        XCTAssertEqual(
            locator.resolve(.ffmpeg, settings: HelperToolSettings())?.path,
            managedFfmpeg.path
        )
    }

    func testIgnoreSystemHelpersEnvironmentEmptiesSystemDirectories() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let locator = HelperToolLocator.standard(
            environment: [HelperToolLocator.ignoreSystemHelpersEnvironmentKey: "1"],
            homeDirectory: home
        )

        XCTAssertTrue(locator.systemDirectories.isEmpty)
    }

    func testToolsDirectoryEnvironmentOverridesManagedRoot() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let custom = URL(fileURLWithPath: "/tmp/custom-nmh-tools", isDirectory: true)
        let locator = HelperToolLocator.standard(
            environment: [HelperToolLocator.toolsDirectoryEnvironmentKey: custom.path],
            homeDirectory: home
        )

        XCTAssertEqual(locator.managedRoot.path, custom.path)
    }

    func testProcessEnvironmentPutsManagedBinFirstWithoutDuplicates() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])
        let managedBin = locator.managedBinDirectory.path

        let base = ["PATH": "\(managedBin):/usr/bin:/bin"]
        let environment = locator.processEnvironment(settings: HelperToolSettings(), base: base)
        let entries = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        XCTAssertEqual(entries.first, managedBin)
        XCTAssertEqual(entries.count, Set(entries).count)
        XCTAssertEqual(entries.filter { $0 == managedBin }.count, 1)
        XCTAssertTrue(entries.contains("/usr/bin"))
    }

    func testIsManaged() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
        let locator = HelperToolLocator(managedRoot: managedRoot, systemDirectories: [])

        XCTAssertTrue(locator.isManaged(locator.managedExecutableURL(for: .ffmpeg)))
        XCTAssertTrue(locator.isManaged(managedRoot.appendingPathComponent("uv/uv")))
        XCTAssertFalse(locator.isManaged(URL(fileURLWithPath: "/usr/local/bin/ffmpeg")))
        XCTAssertFalse(locator.isManaged(URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")))
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelperToolLocatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeExecutable(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
