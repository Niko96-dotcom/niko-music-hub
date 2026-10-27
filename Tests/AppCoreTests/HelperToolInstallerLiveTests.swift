import AppCore
import XCTest

/// Real downloads from the upstream release hosts. Opt-in only:
/// `NMH_LIVE_HELPER_INSTALL=1 swift test --filter HelperToolInstallerLiveTests`
/// (add `NMH_LIVE_HELPER_INSTALL_STEMS=1` for the stem bundle: Python, the pinned demucs-mlx lock and its model).
final class HelperToolInstallerLiveTests: XCTestCase {
    func testDownloadAndConvertInstallsWorkingTools() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NMH_LIVE_HELPER_INSTALL"] == "1")
        try await installAndCheck(.downloadAndConvert)
    }

    /// The home folder starts empty, so the warm-up must download the model itself: the pinned demucs-mlx fetches
    /// its MLX weights (checked against the hashes built into the package) without PyTorch.
    func testStemSeparationInstallsWorkingTool() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NMH_LIVE_HELPER_INSTALL_STEMS"] == "1")
        let (root, home) = try await installAndCheck(.stemSeparation)

        let model = home.appendingPathComponent(".cache/demucs-mlx/htdemucs_ft.safetensors")
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.path), "the warm-up did not download the model")
        let tools = root.appendingPathComponent("uv-tools", isDirectory: true)
        let torch = try FileManager.default.subpathsOfDirectory(atPath: tools.path)
            .filter { $0.hasSuffix("site-packages/torch") }
        XCTAssertEqual(torch, [], "PyTorch is installed")
        print("live stem install: tools \(megabytes(root)) MB, model cache \(megabytes(home)) MB")
    }

    @discardableResult
    private func installAndCheck(_ bundle: HelperToolBundle) async throws -> (root: URL, home: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-live-tools-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Tools", isDirectory: true)
        let home = base.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let locator = HelperToolLocator(managedRoot: root, systemDirectories: [])
        let installer = HelperToolInstaller(
            locator: locator,
            processRunner: FoundationExternalProcessRunner(processGroups: LiveProcessGroupRegistry()),
            homeDirectory: home
        )
        let phases = PhaseLog()

        try await installer.install(bundle) { phases.append($0) }

        XCTAssertTrue(installer.isInstalled(bundle))
        XCTAssertEqual(phases.last?.fractionCompleted, 1)
        for tool in bundle.tools {
            XCTAssertEqual(locator.resolve(tool, settings: HelperToolSettings()), locator.managedExecutableURL(for: tool))
        }
        return (root, home)
    }

    private func megabytes(_ directory: URL) -> Int {
        var bytes = 0
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let file = files?.nextObject() as? URL {
            bytes += (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return bytes / 1_000_000
    }
}

private final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [HelperInstallProgress] = []
    func append(_ item: HelperInstallProgress) { lock.withLock { items.append(item) } }
    var last: HelperInstallProgress? { lock.withLock { items.last } }
}
