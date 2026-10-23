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

    func testDirectoriesAndDirectorySymlinksAreRejectedAtEveryLocation() throws {
        for symbolicLink in [false, true] {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
            let systemDirectory = root.appendingPathComponent("system-bin", isDirectory: true)
            let locator = HelperToolLocator(
                managedRoot: managedRoot,
                systemDirectories: [systemDirectory]
            )
            let configured = root.appendingPathComponent("configured-ffmpeg")
            for candidate in [
                configured,
                locator.managedExecutableURL(for: .ffmpeg),
                systemDirectory.appendingPathComponent("ffmpeg"),
            ] {
                try makeDirectoryCandidate(at: candidate, symbolicLink: symbolicLink)
            }

            let settings = HelperToolSettings(ffmpeg: configured)
            XCTAssertNil(locator.resolve(.ffmpeg, settings: settings))
            XCTAssertFalse(locator.searchDirectories(settings: settings).contains(root))
        }
    }

    func testConfiguredDirectoryFallsBackToManagedOrSystemExecutable() throws {
        for symbolicLink in [false, true] {
            for useManaged in [false, true] {
                let root = try makeTempRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let managedRoot = root.appendingPathComponent("Tools", isDirectory: true)
                let systemDirectory = root.appendingPathComponent("system-bin", isDirectory: true)
                let locator = HelperToolLocator(
                    managedRoot: managedRoot,
                    systemDirectories: [systemDirectory]
                )
                let configured = root.appendingPathComponent("configured-ffmpeg")
                try makeDirectoryCandidate(at: configured, symbolicLink: symbolicLink)
                let managed = locator.managedExecutableURL(for: .ffmpeg)
                let fallback = useManaged ? managed : systemDirectory.appendingPathComponent("ffmpeg")
                try FileManager.default.createDirectory(
                    at: fallback.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try makeExecutable(at: fallback)
                if !useManaged {
                    try makeDirectoryCandidate(at: managed, symbolicLink: symbolicLink)
                }

                XCTAssertEqual(
                    locator.resolve(.ffmpeg, settings: HelperToolSettings(ffmpeg: configured))?.path,
                    fallback.path
                )
            }
        }
    }

    func testExecutableSymlinksResolveAtEveryLocation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let systemDirectory = root.appendingPathComponent("system-bin", isDirectory: true)
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: [systemDirectory]
        )
        let executable = root.appendingPathComponent("executable-target")
        try makeExecutable(at: executable)
        let configured = root.appendingPathComponent("configured-ffmpeg")
        let managed = locator.managedExecutableURL(for: .ffmpeg)
        let system = systemDirectory.appendingPathComponent("ffmpeg")
        for link in [configured, managed, system] {
            try FileManager.default.createDirectory(
                at: link.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        }

        XCTAssertEqual(
            locator.resolve(.ffmpeg, settings: HelperToolSettings(ffmpeg: configured))?.path,
            configured.path
        )
        XCTAssertEqual(locator.resolve(.ffmpeg, settings: HelperToolSettings())?.path, managed.path)
        try FileManager.default.removeItem(at: managed)
        XCTAssertEqual(locator.resolve(.ffmpeg, settings: HelperToolSettings())?.path, system.path)
    }

    func testIgnoreSystemHelpersEnvironmentEmptiesSystemDirectories() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let locator = HelperToolLocator(
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.ignoreSystemHelpersKey: "1"]),
            homeDirectory: home
        )

        XCTAssertTrue(locator.systemDirectories.isEmpty)
    }

    func testToolsDirectoryEnvironmentOverridesManagedRoot() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let custom = URL(fileURLWithPath: "/tmp/custom-nmh-tools", isDirectory: true)
        let locator = HelperToolLocator(
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.helperToolsDirectoryKey: custom.path]),
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
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("HelperToolLocatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeExecutable(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeDirectoryCandidate(at url: URL, symbolicLink: Bool) throws {
        let directory = symbolicLink ? url.appendingPathExtension("directory") : url
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        if symbolicLink {
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: directory)
        }
    }
}
