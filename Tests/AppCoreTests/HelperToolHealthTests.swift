import AppCore
import Foundation
import XCTest

/// One owner of helper status: probes on first ask, after a saved path
/// changes and after an install, and never at launch.
@MainActor
final class HelperToolHealthTests: XCTestCase {
    func testNothingIsProbedUntilASurfaceAsks() async throws {
        let fixture = try HealthFixture(executables: ["/fixture/bin/yt-dlp"])

        XCTAssertTrue(fixture.health.statuses.isEmpty)
        XCTAssertEqual(fixture.runner.count, 0)

        fixture.health.check(.ytDlp)
        try await waitUntil { fixture.health.statuses[.ytDlp] != nil }

        XCTAssertEqual(fixture.health.statuses[.ytDlp], .ready(version: "2027.01.01"))
        XCTAssertEqual(fixture.runner.count, 1)
    }

    func testCheckProbesOnceAndKeepsTheAnswer() async throws {
        let fixture = try HealthFixture(executables: ["/fixture/bin/yt-dlp"])

        fixture.health.check(.ytDlp)
        fixture.health.check(.ytDlp)
        try await waitUntil { fixture.health.statuses[.ytDlp] != nil }
        fixture.health.check(.ytDlp)

        XCTAssertEqual(fixture.runner.count, 1)
    }

    func testASavedHelperPathProbesAgain() async throws {
        let fixture = try HealthFixture(executables: ["/custom/yt-dlp"], ignoresFallback: true)
        fixture.health.check(.ytDlp)
        try await waitUntil { fixture.health.statuses[.ytDlp] != nil }
        XCTAssertEqual(fixture.health.statuses[.ytDlp], .missing)

        try fixture.store.updateSettings { $0.helperTools.ytDlp = URL(fileURLWithPath: "/custom/yt-dlp") }

        try await waitUntil { fixture.health.statuses[.ytDlp] == .ready(version: "2027.01.01") }
    }

    func testAFinishedInstallProbesAgainWhatWasAskedFor() async throws {
        let fixture = try HealthFixture(executables: ["/fixture/bin/yt-dlp"])
        fixture.health.check(.ytDlp)
        try await waitUntil { fixture.runner.count == 1 && fixture.health.statuses[.ytDlp] != nil }

        fixture.health.helpersChanged()

        try await waitUntil { fixture.runner.count == 2 }
        XCTAssertEqual(fixture.runner.requestedPaths, ["/fixture/bin/yt-dlp", "/fixture/bin/yt-dlp"],
                       "FFmpeg and demucs-mlx were never asked for, so they are not probed")
    }

    func testRecheckReturnsTheFreshAnswer() async throws {
        let fixture = try HealthFixture(executables: ["/fixture/bin/ffmpeg"])

        let status = await fixture.health.recheck(.ffmpeg)

        XCTAssertEqual(status, .ready(version: "2027.01.01"))
        XCTAssertEqual(fixture.health.statuses[.ffmpeg], status)
    }

    // MARK: - Source

    /// The two Tools switches are read only by the runtime, and every helper
    /// consumer gets its locator from `HelperToolHealth`.
    func testTheLocatorReadsNoProcessEnvironment() throws {
        let locator = SourceLex.stripped(try SourceTestSupport.read("Sources/AppCore/HelperTools/HelperToolLocator.swift"))
        XCTAssertFalse(locator.contains("ProcessInfo"))
        XCTAssertFalse(locator.contains("NIKO_MUSIC_HUB_"))
    }

    /// Every tool and the shell get the probe and locator from
    /// `ToolContext.helperHealth`; only the composition builds them.
    func testOnlyTheCompositionBuildsAProbeOrALocator() throws {
        let root = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
            guard relative.hasPrefix("Sources/Feature") || relative.hasPrefix("Sources/NikoMusicHub/") else { continue }
            guard relative != "Sources/NikoMusicHub/AppComposition.swift" else { continue }
            let code = SourceLex.stripped(try String(contentsOf: url, encoding: .utf8))
            if code.contains("HelperToolProbe(") || code.contains("HelperToolLocator(") {
                offenders.append(relative)
            }
        }
        XCTAssertEqual(offenders, [], "build them in AppComposition and read ToolContext.helperHealth")
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition did not hold within two seconds") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private struct HealthFixture {
    let store: UserDefaultsSettingsStore
    let runner = CountingRunner()
    let health: HelperToolHealth

    /// `ignoresFallback`: the locator finds a helper only at its saved path.
    init(executables: Set<String>, ignoresFallback: Bool = false) throws {
        store = UserDefaultsSettingsStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: "HelperToolHealthTests.\(UUID())")),
            key: "settings"
        )
        let locator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: ignoresFallback ? [] : [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
        health = HelperToolHealth(
            probe: HelperToolProbe(
                runner: runner,
                referenceDate: Date(timeIntervalSince1970: 1_800_000_000),
                locator: locator
            ),
            appSettings: AppSettingsObserver(store: store)
        )
    }
}

private final class CountingRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var count: Int { lock.withLock { paths.count } }
    var requestedPaths: [String] { lock.withLock { paths } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { paths.append(request.executableURL.path) }
        return ExternalProcessResult(exitCode: 0, standardOutput: "2027.01.01\n", standardError: "")
    }
}
