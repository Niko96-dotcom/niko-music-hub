import Foundation
import XCTest
@testable import NikoMusicCore

final class FileProviderArchiveStorageLiveTests: XCTestCase {
    private let environmentKey = "NIKO_PHASE6_DROPBOX_FIXTURE"
    private let fixtureName = "NikoMusicHub-Phase6-Fixture"
    private let sentinelName = ".niko-phase6-disposable"
    private let sentinelData = Data("niko-music-hub-phase6-disposable-v1\n".utf8)

    func testDisposableDropboxArchiveEvictMaterializeRestoreAndDryRunOpen() async throws {
        guard let configuredPath = ProcessInfo.processInfo.environment[environmentKey] else {
            throw XCTSkip("Set \(environmentKey) to run the destructive disposable Dropbox drill")
        }

        let fileManager = FileManager.default
        let dropboxRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage/Dropbox", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let fixtureRoot = URL(fileURLWithPath: configuredPath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let expectedRoot = dropboxRoot.appendingPathComponent(fixtureName, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()

        XCTAssertEqual(fixtureRoot.path, expectedRoot.path, "live drill is restricted to the dedicated Dropbox fixture")
        guard fixtureRoot.path == expectedRoot.path,
              fixtureRoot.deletingLastPathComponent().path == dropboxRoot.path,
              fixtureRoot.lastPathComponent == fixtureName else {
            XCTFail("refusing non-dedicated Dropbox path")
            return
        }

        try resetOwnedFixture(at: fixtureRoot, fileManager: fileManager)
        defer { removeOwnedFixture(at: fixtureRoot, fileManager: fileManager) }

        let runRoot = fileManager.temporaryDirectory
            .appendingPathComponent("phase6-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: runRoot) }
        let activeRoot = runRoot.appendingPathComponent("Active", isDirectory: true)
        let source = activeRoot.appendingPathComponent("Synthetic Provider Song", isDirectory: true)
        let audio = source.appendingPathComponent("Audio", isDirectory: true)
        try fileManager.createDirectory(at: audio, withIntermediateDirectories: true)
        try Data("synthetic-cubase-project-for-phase6".utf8)
            .write(to: source.appendingPathComponent("Synthetic Provider Song.cpr"))
        try Data((0..<65_536).map { UInt8($0 % 251) })
            .write(to: audio.appendingPathComponent("synthetic-take.wav"))
        let sourceManifest = try VaultManifestBuilder().build(at: source)

        let databaseURL = runRoot.appendingPathComponent("state/vault.sqlite")
        let store = try SQLiteVaultTransferStore(databaseURL: databaseURL)
        let provider = FileProviderArchiveStorage(root: fixtureRoot)
        let capabilities = try await provider.capabilities()
        XCTAssertEqual(
            capabilities,
            StorageCapabilities(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
        )

        let projectID = ProjectID()
        let archiveEngine = try LocalVaultTransferEngine(
            activeRoot: activeRoot,
            archiveRoot: fixtureRoot,
            store: store,
            provider: provider
        )
        let verified = try await archiveEngine.archive(projectID: projectID, sourceURL: source)
        XCTAssertEqual(verified.state, .archiveVerified)
        XCTAssertEqual(verified.durability, .syncedToProvider)
        try VaultManifestBuilder().verify(try XCTUnwrap(verified.manifest), at: verified.destinationURL)
        XCTAssertTrue(fileManager.fileExists(atPath: source.path), "archive must retain Active until removal proof")

        let onlineOnly = try await archiveEngine.removeActiveCopy(after: verified)
        XCTAssertEqual(onlineOnly.state, .archivedOnlineOnly)
        XCTAssertFalse(fileManager.fileExists(atPath: source.path))
        XCTAssertEqual(try store.verifiedArchiveGeneration(projectID: projectID)?.state, .archivedOnlineOnly)

        let catalog = LiveCatalog()
        let workspace = LiveWorkspace()
        let restoreEngine = LocalVaultRestoreEngine(
            activeRoot: activeRoot,
            activeRootID: UUID(),
            resolver: store,
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace)
        )
        let restored = try await restoreEngine.restoreAndOpen(
            projectID: projectID,
            destinationRelativePath: "Restored/Synthetic Provider Song"
        )

        XCTAssertNotNil(restored.completedAt)
        try VaultManifestBuilder().verify(sourceManifest, at: restored.destinationURL)
        try VaultManifestBuilder().verify(try XCTUnwrap(onlineOnly.manifest), at: onlineOnly.destinationURL)
        XCTAssertEqual(catalog.locations.map(\.relativePath), ["Restored/Synthetic Provider Song"])
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Synthetic Provider Song.cpr"])
    }

    private func resetOwnedFixture(at root: URL, fileManager: FileManager) throws {
        let sentinel = root.appendingPathComponent(sentinelName)
        if fileManager.fileExists(atPath: root.path) {
            guard try Data(contentsOf: sentinel) == sentinelData else {
                XCTFail("existing fixture lacks the exact disposable sentinel")
                throw LiveFixtureError.invalidSentinel
            }
            let allowed = Set([sentinelName, ".niko-staging", "generations"])
            let entries = try fileManager.contentsOfDirectory(atPath: root.path)
            guard Set(entries).isSubset(of: allowed) else {
                XCTFail("existing fixture contains unexpected files")
                throw LiveFixtureError.unexpectedContents
            }
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        try sentinelData.write(to: sentinel, options: .atomic)
    }

    private func removeOwnedFixture(at root: URL, fileManager: FileManager) {
        let sentinel = root.appendingPathComponent(sentinelName)
        guard (try? Data(contentsOf: sentinel)) == sentinelData else { return }
        try? fileManager.removeItem(at: root)
    }
}

private enum LiveFixtureError: Error {
    case invalidSentinel
    case unexpectedContents
}

private final class LiveCatalog: ActiveProjectLocationPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLocations: [ProjectLocation] = []
    var locations: [ProjectLocation] { lock.withLock { storedLocations } }

    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {
        lock.withLock { storedLocations.append(location) }
    }
}

private final class LiveWorkspace: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpened: [URL] = []
    var opened: [URL] { lock.withLock { storedOpened } }

    func open(_ url: URL) -> Bool {
        lock.withLock { storedOpened.append(url) }
        return true
    }

    func revealInFinder(_ url: URL) {}
}
