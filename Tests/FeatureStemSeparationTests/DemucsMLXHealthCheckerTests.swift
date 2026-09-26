import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct DemucsMLXHealthCheckerTests {

    private func locator(executables: Set<String>) -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    // MARK: - Discovery

    @Test
    func availability_whenExecutableIsMissing_reportsMissing() async {
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(exitCode: 0, standardOutput: "", standardError: "")),
            locator: locator(executables: [])
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
            locator: locator(executables: [configuredURL.path])
        )
        let health = await checker.availability(settings: HelperToolSettings(demucsMlx: configuredURL))
        #expect(health == .ready(version: "demucs-mlx (htdemucs available)"))
        #expect(runner.lastRequest?.executableURL == configuredURL)
        #expect(runner.lastRequest?.arguments == ["--list-models"])
        #expect(runner.lastRequest?.timeoutSeconds == 30)
    }

    @Test
    func resolvedExecutableURL_fallsBackWhenConfiguredDeleted() {
        let savedDeleted = URL(fileURLWithPath: "/deleted/demucs-mlx")
        let fixture = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            locator: locator(executables: [fixture.path])
        )
        #expect(checker.resolvedExecutableURL(settings: HelperToolSettings(demucsMlx: savedDeleted)) == fixture)
    }

    @Test
    func resolvedExecutableURL_returnsNilWhenNothingResolves() {
        let checker = DemucsMLXHealthChecker(
            locator: locator(executables: [])
        )
        #expect(checker.resolvedExecutableURL(settings: HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/deleted/demucs-mlx"))) == nil)
    }

    @Test
    func availability_whenFixtureExecutableExists_reportsReady() async {
        let fixtureURL = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 0,
                standardOutput: "htdemucs\tStandard 4-source HTDemucs\n",
                standardError: ""
            )),
            locator: locator(executables: [fixtureURL.path])
        )
        let health = await checker.availability(settings: HelperToolSettings(demucsMlx: URL(fileURLWithPath: "/deleted/demucs-mlx")))
        #expect(health == .ready(version: "demucs-mlx (htdemucs available)"))
    }

    // MARK: - Runtime health

    @Test
    func availability_whenVersionCommandFails_reportsUnusable() async {
        let executableURL = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 1,
                standardOutput: "",
                standardError: "Python module not found"
            )),
            locator: locator(executables: [executableURL.path])
        )
        let health = await checker.availability(settings: HelperToolSettings())
        #expect(health == .unusable(message: "Python module not found"))
    }

    @Test
    func availability_whenRunnerThrows_reportsUnusable() async {
        let executableURL = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: ThrowingRunner(),
            locator: locator(executables: [executableURL.path])
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
        let executableURL = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let checker = DemucsMLXHealthChecker(
            runner: FakeRunner(result: .init(
                exitCode: 0,
                standardOutput: "htdemucs\tStandard 4-source HTDemucs\n",
                standardError: ""
            )),
            locator: locator(executables: [executableURL.path])
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
