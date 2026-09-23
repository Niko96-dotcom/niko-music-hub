import AppCore
import XCTest

/// Real downloads from the upstream release hosts. Opt-in only:
/// `NMH_LIVE_HELPER_INSTALL=1 swift test --filter HelperToolInstallerLiveTests`
/// (add `NMH_LIVE_HELPER_INSTALL_STEMS=1` for the ~1 GB stem bundle).
final class HelperToolInstallerLiveTests: XCTestCase {
    func testDownloadAndConvertInstallsWorkingTools() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NMH_LIVE_HELPER_INSTALL"] == "1")
        try await installAndCheck(.downloadAndConvert)
    }

    func testStemSeparationInstallsWorkingTool() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NMH_LIVE_HELPER_INSTALL_STEMS"] == "1")
        try await installAndCheck(.stemSeparation)
    }

    private func installAndCheck(_ bundle: HelperToolBundle) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-live-tools-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = HelperToolLocator(managedRoot: root, systemDirectories: [])
        let installer = HelperToolInstaller(locator: locator)
        let phases = PhaseLog()

        try await installer.install(bundle) { phases.append($0) }

        XCTAssertTrue(installer.isInstalled(bundle))
        XCTAssertEqual(phases.last?.fractionCompleted, 1)
        for tool in bundle.tools {
            XCTAssertEqual(locator.resolve(tool, settings: HelperToolSettings()), locator.managedExecutableURL(for: tool))
        }
    }
}

private final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [HelperInstallProgress] = []
    func append(_ item: HelperInstallProgress) { lock.withLock { items.append(item) } }
    var last: HelperInstallProgress? { lock.withLock { items.last } }
}
