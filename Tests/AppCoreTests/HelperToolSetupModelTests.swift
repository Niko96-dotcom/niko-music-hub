import AppCore
import CryptoKit
import Foundation
import XCTest

@MainActor
final class HelperToolSetupModelTests: XCTestCase {
    func testInitialStatesAreChecking() {
        let locator = HelperToolLocator(managedRoot: URL(fileURLWithPath: "/nonexistent-managed"), systemDirectories: [])
        let model = HelperToolSetupModel(
            locator: locator,
            installer: HelperToolInstaller(locator: locator, processRunner: ExtractingSetupRunner()),
            settingsProvider: { HelperToolSettings() }
        )

        XCTAssertEqual(model.states[.downloadAndConvert], .checking)
        XCTAssertEqual(model.states[.stemSeparation], .checking)
        XCTAssertEqual(model.installGeneration, 0)
        XCTAssertFalse(model.isInstalling)
        XCTAssertFalse(model.allInstalled)
    }

    func testRefreshMapsResolvableToolsToInstalled() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executables = ExecutablePathSet()
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: [],
            isExecutable: { executables.contains($0) }
        )
        let model = HelperToolSetupModel(
            locator: locator,
            installer: HelperToolInstaller(locator: locator, processRunner: ExtractingSetupRunner()),
            settingsProvider: { HelperToolSettings() }
        )

        model.refresh()
        XCTAssertEqual(model.states[.downloadAndConvert], .notInstalled)
        XCTAssertEqual(model.states[.stemSeparation], .notInstalled)

        for tool in HelperToolBundle.downloadAndConvert.tools {
            executables.insert(locator.managedExecutableURL(for: tool).path)
        }
        model.refresh()
        XCTAssertEqual(model.states[.downloadAndConvert], .installed)
        XCTAssertEqual(model.states[.stemSeparation], .notInstalled)
        XCTAssertFalse(model.allInstalled)

        executables.insert(locator.managedExecutableURL(for: .demucsMlx).path)
        model.refresh()
        XCTAssertEqual(model.states[.stemSeparation], .installed)
        XCTAssertTrue(model.allInstalled)
    }

    func testFailedInstallMapsToFailedWithoutBumpingGeneration() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: []
        )
        let installer = HelperToolInstaller(
            locator: locator,
            downloader: FailingSetupDownloader(),
            processRunner: SucceedingSetupRunner()
        )
        let model = HelperToolSetupModel(
            locator: locator,
            installer: installer,
            settingsProvider: { HelperToolSettings() }
        )
        model.refresh()
        XCTAssertEqual(model.states[.downloadAndConvert], .notInstalled)

        model.install(.downloadAndConvert)
        XCTAssertTrue(model.isInstalling)

        try await waitUntilNotInstalling(model)

        XCTAssertFalse(model.isInstalling)
        guard case .failed(let message) = model.states[.downloadAndConvert] else {
            return XCTFail("Expected .failed, got \(String(describing: model.states[.downloadAndConvert]))")
        }
        XCTAssertTrue(message.contains("Could not download"), "Unexpected message: \(message)")
        XCTAssertEqual(model.installGeneration, 0)
        XCTAssertEqual(model.states[.stemSeparation], .notInstalled)
    }

    func testCancelInstallsRefreshesWithoutBumpingGeneration() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: []
        )
        let installer = HelperToolInstaller(
            locator: locator,
            downloader: HangingSetupDownloader(),
            processRunner: SucceedingSetupRunner()
        )
        let model = HelperToolSetupModel(
            locator: locator,
            installer: installer,
            settingsProvider: { HelperToolSettings() }
        )
        model.refresh()

        model.install(.downloadAndConvert)
        XCTAssertTrue(model.isInstalling)
        model.cancelInstalls()

        try await waitUntilNotInstalling(model)

        XCTAssertFalse(model.isInstalling)
        XCTAssertEqual(model.states[.downloadAndConvert], .notInstalled)
        XCTAssertEqual(model.installGeneration, 0)
    }

    func testInstallStartedAfterCancelIsNotClearedByTheCancelledRun() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: []
        )
        let installer = HelperToolInstaller(
            locator: locator,
            downloader: HangingSetupDownloader(),
            processRunner: SucceedingSetupRunner()
        )
        let model = HelperToolSetupModel(
            locator: locator,
            installer: installer,
            settingsProvider: { HelperToolSettings() }
        )
        model.refresh()

        model.install(.downloadAndConvert)
        model.cancelInstalls()
        // Second run starts before the cancelled run has observed its cancellation.
        model.install(.downloadAndConvert)
        XCTAssertTrue(model.isInstalling)

        // Let the cancelled run finish; it must not reset the row the new run owns.
        try await Task.sleep(for: .milliseconds(300))
        guard case .installing = model.states[.downloadAndConvert] else {
            return XCTFail("Cancelled run reset the newer install: \(String(describing: model.states[.downloadAndConvert]))")
        }
        XCTAssertTrue(model.isInstalling)

        model.cancelInstalls()
        try await waitUntilNotInstalling(model)
        XCTAssertEqual(model.states[.downloadAndConvert], .notInstalled)
        XCTAssertEqual(model.installGeneration, 0)

        // The model accepts a fresh install once the last run is really done.
        model.install(.downloadAndConvert)
        XCTAssertTrue(model.isInstalling)
        model.cancelInstalls()
        try await waitUntilNotInstalling(model)
    }

    func testSuccessfulInstallEndsReadyAndBumpsGeneration() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: []
        )
        let installer = HelperToolInstaller(
            locator: locator,
            downloader: ChecksummedSetupDownloader(),
            processRunner: ExtractingSetupRunner()
        )
        let model = HelperToolSetupModel(
            locator: locator,
            installer: installer,
            settingsProvider: { HelperToolSettings() }
        )
        model.refresh()
        XCTAssertEqual(model.states[.downloadAndConvert], .notInstalled)

        model.install(.downloadAndConvert)
        try await waitUntilNotInstalling(model)
        // Let any late progress hop run; it must not flip the row back.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.states[.downloadAndConvert], .installed)
        XCTAssertEqual(model.installGeneration, 1)
    }

    /// Every surface reads helper status from `HelperToolHealth`; an install
    /// tells it, so a Downloader that showed "missing" sees the new yt-dlp.
    func testSuccessfulInstallTellsHelperHealth() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(
            managedRoot: root.appendingPathComponent("Tools", isDirectory: true),
            systemDirectories: []
        )
        let store = UserDefaultsSettingsStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: "HelperToolSetupModelTests.\(UUID())")),
            key: "settings"
        )
        let health = HelperToolHealth(
            probe: HelperToolProbe(runner: VersionAnsweringRunner(), referenceDate: Date(timeIntervalSince1970: 1_800_000_000), locator: locator),
            appSettings: AppSettingsObserver(store: store)
        )
        health.check(.ytDlp)
        try await waitUntil { health.statuses[.ytDlp] == .missing }
        let model = HelperToolSetupModel(
            locator: locator,
            installer: HelperToolInstaller(locator: locator, downloader: ChecksummedSetupDownloader(), processRunner: ExtractingSetupRunner()),
            settingsProvider: { HelperToolSettings() },
            helperHealth: health
        )

        model.install(.downloadAndConvert)

        try await waitUntil { health.statuses[.ytDlp] == .ready(version: "2027.01.01") }
    }

    func testStemCancellationAfterPublicationAndDuringWarmupIsRetryable() async throws {
        for phase in StemSetupGateRunner.Phase.allCases {
            let root = try makeTempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let locator = HelperToolLocator(managedRoot: root, systemDirectories: [])
            let runner = StemSetupGateRunner(phase: phase)
            let installer = HelperToolInstaller(locator: locator, downloader: ChecksummedSetupDownloader(), processRunner: runner)
            let model = HelperToolSetupModel(locator: locator, installer: installer, settingsProvider: { HelperToolSettings() })
            model.refresh()
            model.install(.stemSeparation)
            await runner.waitUntilReached()
            model.cancelInstalls()
            await runner.release()
            try await waitUntilNotInstalling(model)
            XCTAssertFalse(installer.isInstalled(.stemSeparation))
            XCTAssertNil(locator.resolve(.demucsMlx, settings: HelperToolSettings()))
            XCTAssertEqual(model.states[.stemSeparation], .notInstalled)
            model.refresh()
            XCTAssertEqual(model.states[.stemSeparation], .notInstalled)
            XCTAssertEqual(model.installGeneration, 0)
            let staging = root.appendingPathComponent(".staging")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
            model.install(.stemSeparation)
            try await waitUntilNotInstalling(model)
            XCTAssertEqual(model.states[.stemSeparation], .installed)
            XCTAssertEqual(model.installGeneration, 1)
        }
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("HelperToolSetupModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition did not hold within two seconds") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitUntilNotInstalling(_ model: HelperToolSetupModel) async throws {
        for _ in 0..<200 {
            if !model.isInstalling { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for install to finish")
    }
}

private final class ExecutablePathSet: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    func insert(_ path: String) {
        lock.withLock { _ = paths.insert(path) }
    }

    func contains(_ path: String) -> Bool {
        lock.withLock { paths.contains(path) }
    }
}

private final class FailingSetupDownloader: HelperDownloading, @unchecked Sendable {
    func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        throw HelperInstallError.downloadFailed("test-checksums")
    }

    func fetchText(_ url: URL) async throws -> String {
        throw HelperInstallError.downloadFailed("test-checksums")
    }
}

private final class HangingSetupDownloader: HelperDownloading, @unchecked Sendable {
    func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try await Task.sleep(for: .seconds(30))
        try Task.checkCancellation()
        throw CancellationError()
    }

    func fetchText(_ url: URL) async throws -> String {
        try await Task.sleep(for: .seconds(30))
        try Task.checkCancellation()
        throw CancellationError()
    }
}

private final class SucceedingSetupRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

/// Serves fixed bytes and the matching SHA-256 for every checksum URL.
final class ChecksummedSetupDownloader: HelperDownloading, @unchecked Sendable {
    private static let payload = Data("payload".utf8)
    private static var hash: String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    func download(
        _ url: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try Self.payload.write(to: destinationFile)
        progress(1)
        return url
    }

    func fetchText(_ url: URL) async throws -> String {
        "\(Self.hash)  yt-dlp_macos\n"
    }
}

/// ditto "extracts" an executable named after the zip; every other call succeeds.
private final class ExtractingSetupRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        if request.executableURL.path == "/usr/bin/ditto", request.arguments.count == 4 {
            let name = URL(fileURLWithPath: request.arguments[2]).deletingPathExtension().lastPathComponent
            let target = URL(fileURLWithPath: request.arguments[3]).appendingPathComponent(name)
            FileManager.default.createFile(atPath: target.path, contents: Data("bin".utf8))
        }
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        try await run(request)
    }
}

/// Answers every helper's version check with a current yt-dlp version.
private struct VersionAnsweringRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        ExternalProcessResult(exitCode: 0, standardOutput: "2027.01.01\n", standardError: "")
    }
}
