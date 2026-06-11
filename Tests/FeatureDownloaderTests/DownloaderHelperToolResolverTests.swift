@testable import FeatureDownloader
import AppCore
import XCTest

final class DownloaderHelperToolResolverTests: XCTestCase {
    func testFfmpegLocationPrefersConfiguredPath() {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/custom/helpers/ffmpeg")
        )
        let location = DownloaderHelperToolResolver.ffmpegLocationURL(
            settings: settings,
            fileExists: { $0 == "/custom/helpers/ffmpeg" }
        )
        XCTAssertEqual(location?.path, "/custom/helpers")
    }

    func testFfmpegLocationFallsBackToCommonDirectories() {
        let settings = HelperToolSettings(ffmpeg: nil)
        let location = DownloaderHelperToolResolver.ffmpegLocationURL(
            settings: settings,
            fileExists: { $0 == "/opt/homebrew/bin/ffmpeg" }
        )
        XCTAssertEqual(location?.path, "/opt/homebrew/bin")
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

    func testHelperSearchDirectoriesIncludeConfiguredAndCommonPaths() {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/custom/bin/ffmpeg"),
            ytDlp: URL(fileURLWithPath: "/custom/bin/yt-dlp")
        )
        let directories = DownloaderHelperToolResolver.helperSearchDirectories(
            settings: settings,
            fileExists: { path in
                path == "/custom/bin/yt-dlp" || path == "/custom/bin/ffmpeg"
            }
        )
        let paths = Set(directories.map(\.path))
        XCTAssertTrue(paths.contains("/custom/bin"))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
    }
}
