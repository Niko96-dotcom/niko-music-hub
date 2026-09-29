import AppCore
import Foundation
import NikoMusicCore

final class VaultOffCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// B-002 fixture: Vault configured (Active + Archive roots) but switched OFF, plus a
/// retained generation with a fixture file whose bytes must never change.
struct VaultOffOutputFixture {
    struct Destination {
        let label: String
        let url: URL
    }

    struct ArchiveSnapshot: Equatable {
        let entries: [String]
        let fixtureBytes: Data
    }

    let base: URL
    let active: URL
    let archive: URL
    let generation: URL
    let archiveAlias: URL
    let ordinaryOutput: URL
    let input: URL
    let fixtureFile: URL

    init() throws {
        let fileManager = FileManager.default
        base = fileManager.temporaryDirectory
            .appendingPathComponent("vault-off-output-\(UUID().uuidString)", isDirectory: true)
        active = base.appendingPathComponent("Active", isDirectory: true)
        archive = base.appendingPathComponent("Archive", isDirectory: true)
        generation = archive.appendingPathComponent("Song/generation-1", isDirectory: true)
        archiveAlias = base.appendingPathComponent("archive-alias", isDirectory: true)
        ordinaryOutput = base.appendingPathComponent("Outputs", isDirectory: true)
        input = base.appendingPathComponent("input.wav", isDirectory: false)
        fixtureFile = generation.appendingPathComponent("manifest.json", isDirectory: false)

        try fileManager.createDirectory(at: active, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: generation, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: ordinaryOutput, withIntermediateDirectories: true)
        try Data("retained-generation-manifest".utf8).write(to: fixtureFile)
        try Data("input".utf8).write(to: input)
        try fileManager.createSymbolicLink(at: archiveAlias, withDestinationURL: archive)
    }

    var refusedDestinations: [Destination] {
        [
            Destination(label: "archive root", url: archive),
            Destination(label: "folder inside archive", url: generation),
            Destination(
                label: "missing folder inside archive",
                url: archive.appendingPathComponent("New Output", isDirectory: true)
            ),
            Destination(label: "symlink alias of archive", url: archiveAlias),
            Destination(
                label: "missing folder below archive alias",
                url: archiveAlias.appendingPathComponent("New Output", isDirectory: true)
            ),
        ]
    }

    func settings(outputFolder: URL) -> AppSettings {
        let activeRoot = StoredMusicRoot(role: .active, url: active)
        let archiveRoot = StoredMusicRoot(role: .archive, url: archive)
        var settings = AppSettings(outputFolder: StoredFolderLocation(url: outputFolder))
        settings.musicRoots = [activeRoot, archiveRoot]
        settings.vault.activeRootID = activeRoot.id
        settings.vault.archiveRootID = archiveRoot.id
        settings.vault.isEnabled = false
        return settings
    }

    /// Recursive listing of the archive plus the fixture file's bytes.
    func archiveSnapshot() throws -> ArchiveSnapshot {
        let entries = (FileManager.default.enumerator(atPath: archive.path)?.allObjects as? [String] ?? []).sorted()
        return ArchiveSnapshot(entries: entries, fixtureBytes: try Data(contentsOf: fixtureFile))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }
}
