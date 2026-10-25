import AppCore
import XCTest

/// One probe for every helper. The cases come from the three checkers it
/// replaced (FFmpeg, yt-dlp, demucs-mlx); what they assert is unchanged.
final class HelperToolProbeTests: XCTestCase {
    private func locator(executables: Set<String>) -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    private func probe(
        executables: Set<String>,
        runner: any ExternalProcessRunning = ProbeRunner(.failure(ProbeError.notCalled)),
        referenceDate: Date? = nil
    ) -> HelperToolProbe {
        HelperToolProbe(runner: runner, referenceDate: referenceDate, locator: locator(executables: executables))
    }

    private static func output(_ text: String, exitCode: Int32 = 0, error: String = "") -> ProbeRunner {
        ProbeRunner(.success(ExternalProcessResult(exitCode: exitCode, standardOutput: text, standardError: error)))
    }

    // MARK: - Missing

    func testMissingWhenNothingResolves() async {
        for tool in [HelperTool.ytDlp, .ffmpeg, .demucsMlx] {
            let status = await probe(executables: []).status(of: tool, settings: HelperToolSettings())
            XCTAssertEqual(status, .missing, "\(tool)")
        }
    }

    func testMissingWhenTheSavedPathIsNotOnDisk() async {
        let settings = HelperToolSettings(
            ffmpeg: URL(fileURLWithPath: "/missing/ffmpeg"),
            ytDlp: URL(fileURLWithPath: "/nonexistent/yt-dlp"),
            demucsMlx: URL(fileURLWithPath: "/deleted/demucs-mlx")
        )
        for tool in [HelperTool.ytDlp, .ffmpeg, .demucsMlx] {
            let status = await probe(executables: []).status(of: tool, settings: settings)
            XCTAssertEqual(status, .missing, "\(tool)")
        }
    }

    func testADeletedSavedPathFallsBackToTheSystemFolder() async {
        let fixture = "/fixture/bin/yt-dlp"
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/deleted/yt-dlp"))
        let runner = RecordingProbeRunner(output: "2027.01.01\n")
        let probe = probe(executables: [fixture], runner: runner, referenceDate: Date(timeIntervalSince1970: 1_800_000_000))

        let status = await probe.status(of: .ytDlp, settings: settings)

        XCTAssertEqual(status, .ready(version: "2027.01.01"))
        XCTAssertEqual(runner.requests.first?.executableURL.path, fixture)
    }

    // MARK: - yt-dlp

    func testYtDlpReadyWithItsVersionAndAFiveSecondTimeout() async {
        let runner = RecordingProbeRunner(output: "2027.01.01\n")
        let executable = URL(fileURLWithPath: "/usr/local/bin/yt-dlp")
        let probe = probe(executables: [executable.path], runner: runner, referenceDate: Date(timeIntervalSince1970: 1_800_000_000))

        let status = await probe.status(of: .ytDlp, settings: HelperToolSettings(ytDlp: executable))

        XCTAssertEqual(status, .ready(version: "2027.01.01"))
        XCTAssertEqual(runner.requests, [
            ExternalProcessRequest(executableURL: executable, arguments: ["--version"], timeoutSeconds: 5)
        ])
    }

    func testYtDlpOutdatedWhenOlderThan90Days() async {
        let executable = URL(fileURLWithPath: "/usr/local/bin/yt-dlp")
        let probe = probe(
            executables: [executable.path],
            runner: Self.output("2024.01.01\n"),
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let status = await probe.status(of: .ytDlp, settings: HelperToolSettings(ytDlp: executable))

        guard case let .outdated(current, minimumExpected) = status else {
            return XCTFail("Expected .outdated, got \(status)")
        }
        XCTAssertEqual(current, "2024.01.01")
        XCTAssertFalse(minimumExpected.isEmpty)
    }

    func testYtDlpOutdatedWhenOlderThanTheYouTubeCompatibilityRelease() async throws {
        let reference = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 24)
        ))
        let executable = URL(fileURLWithPath: "/usr/local/bin/yt-dlp")
        let probe = probe(executables: [executable.path], runner: Self.output("2026.07.04\n"), referenceDate: reference)

        let status = await probe.status(of: .ytDlp, settings: HelperToolSettings(ytDlp: executable))

        XCTAssertEqual(status, .outdated(current: "2026.07.04", minimumExpected: "2026.08.19"))
    }

    func testYtDlpBrokenWhenTheProcessThrows() async {
        let executable = URL(fileURLWithPath: "/usr/local/bin/yt-dlp")
        let probe = probe(executables: [executable.path], runner: ProbeRunner(.failure(ProbeError.expected)))

        let status = await probe.status(of: .ytDlp, settings: HelperToolSettings(ytDlp: executable))

        XCTAssertEqual(status, .broken(message: "Expected process failure"))
    }

    // MARK: - FFmpeg

    func testFFmpegReadyWithItsFirstLineAndAFifteenSecondTimeout() async {
        let runner = RecordingProbeRunner(output: "ffmpeg version 8.1 Copyright\nconfiguration: test")
        let executable = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let probe = probe(executables: [executable.path], runner: runner)

        let status = await probe.status(of: .ffmpeg, settings: HelperToolSettings(ffmpeg: executable))

        XCTAssertEqual(status, .ready(version: "ffmpeg version 8.1 Copyright"))
        XCTAssertEqual(runner.requests, [
            ExternalProcessRequest(executableURL: executable, arguments: ["-version"], timeoutSeconds: 15)
        ])
    }

    func testFFmpegBrokenWithItsErrorOutput() async {
        let executable = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let probe = probe(executables: [executable.path], runner: Self.output("", exitCode: 1, error: "bad helper"))

        let status = await probe.status(of: .ffmpeg, settings: HelperToolSettings(ffmpeg: executable))

        XCTAssertEqual(status, .broken(message: "bad helper"))
    }

    func testFFmpegBrokenWhenTheRunnerThrows() async {
        let executable = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let probe = probe(executables: [executable.path], runner: ProbeRunner(.failure(ProbeError.expected)))

        let status = await probe.status(of: .ffmpeg, settings: HelperToolSettings(ffmpeg: executable))

        XCTAssertEqual(status, .broken(message: "Expected process failure"))
    }

    func testAFailedRunWithNoOutputNamesTheHelperAndItsExitCode() async {
        let executable = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let probe = probe(executables: [executable.path], runner: Self.output("", exitCode: 3))

        let status = await probe.status(of: .ffmpeg, settings: HelperToolSettings(ffmpeg: executable))

        XCTAssertEqual(status, .broken(message: "FFmpeg exited with code 3."))
    }

    // MARK: - demucs-mlx

    func testDemucsReadyNamesItsFirstModelWithAThirtySecondTimeout() async {
        let runner = RecordingProbeRunner(output: "htdemucs\tStandard 4-source HTDemucs\n")
        let configured = URL(fileURLWithPath: "/custom/demucs-mlx")
        let probe = probe(executables: [configured.path], runner: runner)

        let status = await probe.status(of: .demucsMlx, settings: HelperToolSettings(demucsMlx: configured))

        XCTAssertEqual(status, .ready(version: "demucs-mlx (htdemucs available)"))
        XCTAssertEqual(runner.requests, [
            ExternalProcessRequest(executableURL: configured, arguments: ["--list-models"], timeoutSeconds: 30)
        ])
    }

    func testDemucsBrokenWithItsErrorOutput() async {
        let executable = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let probe = probe(executables: [executable.path], runner: Self.output("", exitCode: 1, error: "Python module not found"))

        let status = await probe.status(of: .demucsMlx, settings: HelperToolSettings())

        XCTAssertEqual(status, .broken(message: "Python module not found"))
    }
}

private struct ProbeRunner: ExternalProcessRunning {
    let result: Result<ExternalProcessResult, ProbeError>

    init(_ result: Result<ExternalProcessResult, ProbeError>) {
        self.result = result
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try result.get()
    }
}

private final class RecordingProbeRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var recorded: [ExternalProcessRequest] = []

    var requests: [ExternalProcessRequest] { lock.withLock { recorded } }

    init(output: String) {
        self.output = output
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { recorded.append(request) }
        return ExternalProcessResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}

private enum ProbeError: LocalizedError {
    case expected
    case notCalled

    var errorDescription: String? {
        switch self {
        case .expected: "Expected process failure"
        case .notCalled: "runner should not be called"
        }
    }
}
