import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct DemucsMLXHealthCheckerTests {

    // MARK: - Discovery

    @Test
    func availability_whenExecutableIsMissing_reportsMissing() async {
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(exitCode: 0, standardOutput: "", standardError: "")),
            fileExists: { _ in false }
        )
        let health = await checker.availability(settings: HelperToolSettings())
        #expect(health == .missing)
    }

    @Test
    func availability_usesConfiguredPathOverride() async {
        let configuredURL = URL(fileURLWithPath: "/custom/demucs-mlx")
        let runner = FakeRunner(result: .init(
            exitCode: 0,
            standardOutput: "htdemucs\tStandard 4-source HTDemucs\n",
            standardError: ""
        ))
        let checker = DemucsMLXHealthChecker(
            runner: runner,
            fileExists: { path in path == configuredURL.path }
        )
        let health = await checker.availability(settings: HelperToolSettings(demucsMlx: configuredURL))
        #expect(health == .ready(version: "demucs-mlx (htdemucs available)"))
        #expect(runner.lastRequest?.executableURL == configuredURL)
        #expect(runner.lastRequest?.arguments == ["--list-models"])
    }

    @Test
    func detectExecutable_findsKnownPathWithoutPATH() {
        let foundURL = DemucsMLXHealthChecker.detectExecutable { path in
            path == "/opt/homebrew/bin/demucs-mlx"
        }
        #expect(foundURL == URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx"))
    }

    @Test
    func detectExecutable_returnsNilWhenNoKnownPathExists() {
        let foundURL = DemucsMLXHealthChecker.detectExecutable { _ in false }
        #expect(foundURL == nil)
    }

    // MARK: - Runtime health

    @Test
    func availability_whenVersionCommandFails_reportsUnusable() async {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 1,
                standardOutput: "",
                standardError: "Python module not found"
            )),
            fileExists: { path in path == executableURL.path }
        )
        let health = await checker.availability(settings: HelperToolSettings())
        #expect(health == .unusable(message: "Python module not found"))
    }

    @Test
    func availability_whenRunnerThrows_reportsUnusable() async {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: ThrowingRunner(),
            fileExists: { path in path == executableURL.path }
        )
        let health = await checker.availability(settings: HelperToolSettings())
        if case .unusable = health {
            // pass
        } else {
            Issue.record("Expected unusable state, got \(health)")
        }
    }

    @Test
    func availability_whenExecutableRunsWithoutCachedModels_reportsReady() async {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 0,
                standardOutput: "htdemucs\tStandard 4-source HTDemucs\n",
                standardError: ""
            )),
            fileExists: { path in path == executableURL.path }
        )
        let health = await checker.availability(settings: HelperToolSettings())
        #expect(health == .ready(version: "demucs-mlx (htdemucs available)"))
    }

    @Test
    func availability_whenEverythingAvailable_reportsReady() async {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 0,
                standardOutput: "htdemucs\tStandard 4-source HTDemucs\n",
                standardError: ""
            )),
            fileExists: { path in path == executableURL.path }
        )
        let health = await checker.availability(settings: HelperToolSettings())
        #expect(health == .ready(version: "demucs-mlx (htdemucs available)"))
    }
}

// MARK: - Fakes

private final class FakeRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?
    private let result: ExternalProcessResult

    var lastRequest: ExternalProcessRequest? { lock.withLock { request } }

    init(result: ExternalProcessResult) {
        self.result = result
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { self.request = request }
        return result
    }
}

private struct ThrowingRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        struct TestError: LocalizedError {}
        throw TestError()
    }
}
