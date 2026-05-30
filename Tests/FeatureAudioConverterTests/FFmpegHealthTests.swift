import AppCore
import FeatureAudioConverter
import XCTest

final class FFmpegHealthTests: XCTestCase {
    func testMissingWhenPathIsNilAndAutoDetectUnavailable() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            fileExists: { _ in false }
        )

        let availability = await checker.availability(settings: HelperToolSettings(ffmpeg: nil))

        XCTAssertEqual(availability, .missing)
    }

    func testMissingWhenPathDoesNotExist() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            fileExists: { _ in false }
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/missing/ffmpeg"))
        )

        XCTAssertEqual(availability, .missing)
    }

    func testResolvedFFmpegURLUsesAutoDetectWhenSettingsUnset() {
        let detected = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            )),
            fileExists: { $0 == detected.path }
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
            fileExists: { $0 == configured.path }
        )

        XCTAssertEqual(
            checker.resolvedFFmpegURL(settings: HelperToolSettings(ffmpeg: configured)),
            configured
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
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let checker = FFmpegHealthChecker(runner: runner, fileExists: { _ in true })

        let availability = await checker.availability(settings: HelperToolSettings(ffmpeg: ffmpegURL))

        XCTAssertEqual(availability, .available(version: "ffmpeg version 8.1 Copyright"))
        XCTAssertEqual(runner.requests, [
            ExternalProcessRequest(executableURL: ffmpegURL, arguments: ["-version"])
        ])
    }

    func testUnusableWhenVersionCommandFails() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad helper")
            )),
            fileExists: { _ in true }
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"))
        )

        XCTAssertEqual(availability, .unusable(message: "bad helper"))
    }

    func testUnusableWhenRunnerThrows() async {
        let checker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .failure(SampleProcessError.expected)),
            fileExists: { _ in true }
        )

        let availability = await checker.availability(
            settings: HelperToolSettings(ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"))
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
