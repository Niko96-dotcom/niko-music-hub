import AppCore
@testable import FeatureDownloader
import XCTest

final class YtDlpHealthCheckerTests: XCTestCase {
    private func locator(executables: Set<String>) -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    func testMissingWhenConfiguredPathDoesNotExistOnDisk() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/nonexistent/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysFailingRunner(),
            locator: locator(executables: [])
        )
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testMissingWhenNilPathAndAutoDetectPathMissingOnDisk() async {
        let settings = HelperToolSettings(ytDlp: nil)
        let checker = YtDlpHealthChecker(
            runner: AlwaysFailingRunner(),
            locator: locator(executables: [])
        )
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testMissingWhenFileDoesNotExist() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysFailingRunner(),
            locator: locator(executables: [])
        )
        let result = await checker.availability(settings: settings)
        XCTAssertEqual(result, .missing)
    }

    func testAvailableWhenVersionCommandSucceeds() async {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysSucceedingRunner(output: "2027.01.01\n"),
            referenceDate: reference,
            locator: locator(executables: ["/usr/local/bin/yt-dlp"])
        )
        let result = await checker.availability(settings: settings)
        guard case let .available(version) = result else {
            return XCTFail("Expected .available, got \(result)")
        }
        XCTAssertEqual(version, "2027.01.01")
    }

    func testOutdatedWhenVersionOlderThan90Days() async {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysSucceedingRunner(output: "2024.01.01\n"),
            referenceDate: reference,
            locator: locator(executables: ["/usr/local/bin/yt-dlp"])
        )
        let result = await checker.availability(settings: settings)
        guard case let .outdated(current, minimumExpected) = result else {
            return XCTFail("Expected .outdated, got \(result)")
        }
        XCTAssertEqual(current, "2024.01.01")
        XCTAssertFalse(minimumExpected.isEmpty)
    }

    func testOutdatedWhenVersionPredatesCurrentYouTubeCompatibilityRelease() async {
        let reference = Calendar(identifier: .gregorian).date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 8,
                day: 24
            )
        )!
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: AlwaysSucceedingRunner(output: "2026.07.04\n"),
            referenceDate: reference,
            locator: locator(executables: ["/usr/local/bin/yt-dlp"])
        )

        let result = await checker.availability(settings: settings)

        XCTAssertEqual(
            result,
            .outdated(current: "2026.07.04", minimumExpected: "2026.08.19")
        )
    }

    func testUnusableWhenProcessThrows() async {
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: ThrowingRunner(),
            locator: locator(executables: ["/usr/local/bin/yt-dlp"])
        )
        let result = await checker.availability(settings: settings)
        guard case let .unusable(message) = result else {
            return XCTFail("Expected .unusable, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testSavedDeletedPathFallsBackToFixtureExecutable() async {
        let savedDeleted = URL(fileURLWithPath: "/deleted/yt-dlp")
        let fixture = URL(fileURLWithPath: "/fixture/bin/yt-dlp")
        let settings = HelperToolSettings(ytDlp: savedDeleted)
        let checker = YtDlpHealthChecker(
            runner: AlwaysSucceedingRunner(output: "2027.01.01\n"),
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000),
            locator: locator(executables: [fixture.path])
        )
        let result = await checker.availability(settings: settings)
        guard case .available = result else {
            return XCTFail("Expected .available via fallback, got \(result)")
        }
        XCTAssertEqual(checker.resolvedYtDlpURL(settings: settings), fixture)
    }

    func testResolvedYtDlpURLFallsBackWhenConfiguredDeleted() {
        let savedDeleted = URL(fileURLWithPath: "/deleted/yt-dlp")
        let fixture = URL(fileURLWithPath: "/fixture/bin/yt-dlp")
        let checker = YtDlpHealthChecker(
            locator: locator(executables: [fixture.path])
        )
        XCTAssertEqual(
            checker.resolvedYtDlpURL(settings: HelperToolSettings(ytDlp: savedDeleted)),
            fixture
        )
    }

    func testVersionProbeUsesFiveSecondTimeout() async {
        let executable = URL(fileURLWithPath: "/fixture/bin/yt-dlp")
        let runner = CapturingRunner(output: "2027.01.01\n")
        let checker = YtDlpHealthChecker(
            runner: runner,
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000),
            locator: locator(executables: [executable.path])
        )
        _ = await checker.availability(settings: HelperToolSettings(ytDlp: executable))
        XCTAssertEqual(runner.lastRequest?.timeoutSeconds, 5)
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

private final class CapturingRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var request: ExternalProcessRequest?

    var lastRequest: ExternalProcessRequest? { lock.withLock { request } }

    init(output: String) {
        self.output = output
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { self.request = request }
        return .init(exitCode: 0, standardOutput: output, standardError: "")
    }
}
