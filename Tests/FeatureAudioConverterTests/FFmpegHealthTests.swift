import AppCore
import FeatureAudioConverter
import XCTest

final class FFmpegHealthTests: XCTestCase {
    private func locator(executables: Set<String>) -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    func testMissingWhenPathIsNilAndAutoDetectUnavailable() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            locator: locator(executables: [])
        )

        let availability = await checker.availability(settings: HelperToolSettings(ffmpeg: nil))

        XCTAssertEqual(availability, .missing)
    }

    func testMissingWhenPathDoesNotExist() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            locator: locator(executables: [])
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/missing/ffmpeg"))
        )

        XCTAssertEqual(availability, .missing)
    }

    func testResolvedFFmpegURLUsesAutoDetectWhenSettingsUnset() {
        let detected = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            locator: locator(executables: [detected.path])
        )

        XCTAssertEqual(
            checker.resolvedFFmpegURL(settings: HelperToolSettings(ffmpeg: nil)),
            detected
        )
    }

    func testResolvedFFmpegURLPrefersConfiguredPath() {
        let configured = URL(fileURLWithPath: "/custom/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            locator: locator(executables: [configured.path])
        )

        XCTAssertEqual(
            checker.resolvedFFmpegURL(settings: HelperToolSettings(ffmpeg: configured)),
            configured
        )
    }

    func testSavedDeletedPathFallsBackToFixtureExecutable() {
        let savedDeleted = URL(fileURLWithPath: "/deleted/ffmpeg")
        let fixture = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            locator: locator(executables: [fixture.path])
        )
        XCTAssertEqual(
            checker.resolvedFFmpegURL(settings: HelperToolSettings(ffmpeg: savedDeleted)),
            fixture
        )
    }

    func testAvailableWhenVersionCommandSucceeds() async {
        let runner = RecordingExternalProcessRunner(result: .success(
            ExternalProcessResult(
                exitCode: 0,
                standardOutput: "ffmpeg version 8.1 Copyright\nconfiguration: test",
                standardError: ""
            )
        ))
        let ffmpegURL = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            runner: runner,
            locator: locator(executables: [ffmpegURL.path])
        )

        let availability = await checker.availability(settings: HelperToolSettings(ffmpeg: ffmpegURL))

        XCTAssertEqual(availability, .available(version: "ffmpeg version 8.1 Copyright"))
        XCTAssertEqual(runner.requests, [
            ExternalProcessRequest(executableURL: ffmpegURL, arguments: ["-version"], timeoutSeconds: 15)
        ])
    }

    func testUnusableWhenVersionCommandFails() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad helper")
            )),
            locator: locator(executables: ["/fixture/bin/ffmpeg"])
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/fixture/bin/ffmpeg"))
        )

        XCTAssertEqual(availability, .unusable(message: "bad helper"))
    }

    func testUnusableWhenRunnerThrows() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .failure(SampleProcessError.expected)),
            locator: locator(executables: ["/fixture/bin/ffmpeg"])
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/fixture/bin/ffmpeg"))
        )

        XCTAssertEqual(availability, .unusable(message: "Expected process failure"))
    }
}

private final class RecordingExternalProcessRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<ExternalProcessResult, Error>
    private var storedRequests: [ExternalProcessRequest] = []

    var requests: [ExternalProcessRequest] {
        lock.withLock { storedRequests }
    }

    init(result: Result<ExternalProcessResult, Error>) {
        self.result = result
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock {
            storedRequests.append(request)
        }
        return try result.get()
    }
}

private struct FakeExternalProcessRunner: ExternalProcessRunning {
    var result: Result<ExternalProcessResult, Error>

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try result.get()
    }
}

private enum SampleProcessError: LocalizedError {
    case expected

    var errorDescription: String? {
        switch self {
        case .expected:
            "Expected process failure"
        }
    }
}
