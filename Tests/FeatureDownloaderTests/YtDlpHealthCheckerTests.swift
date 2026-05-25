import AppCore
@testable import FeatureDownloader
import XCTest

final class YtDlpHealthCheckerTests: XCTestCase {
    func testMissingWhenConfiguredPathDoesNotExistOnDisk() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/nonexistent/yt-dlp"))
        let checker = YtDlpHealthChecker(runner: AlwaysFailingRunner(), fileExists: { _ in false })
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testMissingWhenNilPathAndAutoDetectPathMissingOnDisk() async {
        let settings = HelperToolSettings(ytDlp: nil)
        let checker = YtDlpHealthChecker(runner: AlwaysFailingRunner(), fileExists: { _ in false })
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testMissingWhenFileDoesNotExist() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(runner: AlwaysFailingRunner(), fileExists: { _ in false })
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testAvailableWhenVersionCommandSucceeds() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysSucceedingRunner(output: "2024.03.17\n"),
            fileExists: { _ in true }
        )
        let result = await checker.availability(settings: settings)
        guard case let .available(version) = result else {
            return XCTFail("Expected .available, got \(result)")
        }
        XCTAssertEqual(version, "2024.03.17")
    }

    func testUnusableWhenProcessThrows() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(runner: ThrowingRunner(), fileExists: { _ in true })
        let result = await checker.availability(settings: settings)
        guard case let .unusable(message) = result else {
            return XCTFail("Expected .unusable, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testNoShellStringsInSource() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureDownloader/YtDlpHealthChecker.swift",
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("/bin/sh"))
        XCTAssertFalse(source.contains("sh\", \"-c"))
        XCTAssertFalse(source.contains("shell"))
    }
}

private struct AlwaysFailingRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "runner should not be called"])
    }
}

private struct AlwaysSucceedingRunner: ExternalProcessRunning {
    private let output: String

    init(output: String) {
        self.output = output
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 0, standardOutput: output, standardError: "")
    }
}

private struct ThrowingRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        throw NSError(domain: "test", code: 1)
    }
}
