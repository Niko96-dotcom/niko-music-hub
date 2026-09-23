@testable import FeatureDownloader
import AppCore
import XCTest

final class DownloaderHelperToolResolverTests: XCTestCase {
    private func locator(executables: Set<String>, managedRoot: String = "/nonexistent-managed") -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: managedRoot, isDirectory: true),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    func testFfmpegLocationPrefersConfiguredPath() {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/custom/helpers/ffmpeg")
        )
        let location = DownloaderHelperToolResolver.ffmpegLocationURL(
            settings: settings,
            locator: locator(executables: ["/custom/helpers/ffmpeg"])
        )
        XCTAssertEqual(location?.path, "/custom/helpers")
    }

    func testFfmpegLocationFallsBackToSystemDirectories() {
        let settings = HelperToolSettings(ffmpeg: nil)
        let location = DownloaderHelperToolResolver.ffmpegLocationURL(
            settings: settings,
            locator: locator(executables: ["/fixture/bin/ffmpeg"])
        )
        XCTAssertEqual(location?.path, "/fixture/bin")
    }

    func testFfmpegLocationIsNilWhenNothingResolves() {
        let settings = HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/deleted/ffmpeg"))
        let location = DownloaderHelperToolResolver.ffmpegLocationURL(
            settings: settings,
            locator: locator(executables: [])
        )
        XCTAssertNil(location)
    }

    func testProcessEnvironmentPrependsHelperDirectoriesToStrippedPath() {
        let directories = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        ]
        let environment = DownloaderHelperToolResolver.processEnvironment(
            helperSearchDirectories: directories,
            base: ["PATH": "/usr/bin:/bin"]
        )
        XCTAssertEqual(
            environment?["PATH"],
            "/opt/homebrew/bin:/usr/bin:/bin"
        )
    }

    func testProcessEnvironmentDedupesDirectories() {
        let directories = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        ]
        let environment = DownloaderHelperToolResolver.processEnvironment(
            helperSearchDirectories: directories,
            base: ["PATH": "/usr/bin:/bin"]
        )
        XCTAssertEqual(
            environment?["PATH"],
            "/opt/homebrew/bin:/usr/bin:/bin"
        )
    }

    func testProcessEnvironmentReturnsNilWhenNoDirectories() {
        let environment = DownloaderHelperToolResolver.processEnvironment(
            helperSearchDirectories: [],
            base: ["PATH": "/usr/bin:/bin"]
        )
        XCTAssertNil(environment)
    }

    func testHelperSearchDirectoriesIncludeConfiguredAndSystemPaths() {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/custom/bin/ffmpeg"),
            ytDlp: URL(fileURLWithPath: "/custom/bin/yt-dlp")
        )
        let directories = DownloaderHelperToolResolver.helperSearchDirectories(
            settings: settings,
            locator: locator(executables: ["/custom/bin/yt-dlp", "/custom/bin/ffmpeg"])
        )
        let paths = Set(directories.map(\.path))
        XCTAssertTrue(paths.contains("/custom/bin"))
        XCTAssertTrue(paths.contains("/fixture/bin"))
    }

    func testSettingsProcessEnvironmentUsesLocator() {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/custom/bin/ffmpeg")
        )
        let environment = DownloaderHelperToolResolver.processEnvironment(
            settings: settings,
            base: ["PATH": "/usr/bin:/bin"],
            locator: locator(executables: ["/custom/bin/ffmpeg"])
        )
        let path = environment?["PATH"] ?? ""
        XCTAssertTrue(path.contains("/custom/bin"))
        XCTAssertTrue(path.contains("/usr/bin:/bin"))
    }
}
