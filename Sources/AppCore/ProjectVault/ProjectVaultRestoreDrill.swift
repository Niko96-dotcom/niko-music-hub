import Foundation
import NikoMusicCore

public struct ProjectVaultRestoreDrillResult: Equatable, Sendable {
    public let completedAt: Date
    public let fileCount: Int
    public let archiveCopyPreserved: Bool

    public init(completedAt: Date, fileCount: Int, archiveCopyPreserved: Bool) {
        self.completedAt = completedAt
        self.fileCount = fileCount
        self.archiveCopyPreserved = archiveCopyPreserved
    }
}

/// A deliberately self-contained restore rehearsal. It creates its own tiny Cubase-like
/// fixture below a fresh temporary directory and never resolves or touches configured roots.
public struct ProjectVaultRestoreDrill: @unchecked Sendable {
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
        self.now = now
    }

    public func run() throws -> ProjectVaultRestoreDrillResult {
        let root = temporaryDirectory.appendingPathComponent("niko-vault-restore-drill-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let archive = root.appendingPathComponent("archive/generation", isDirectory: true)
        let staging = root.appendingPathComponent("active/.niko-staging/fixture", isDirectory: true)
        let restored = root.appendingPathComponent("active/Restored Fixture", isDirectory: true)
        try fileManager.createDirectory(at: archive.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try Data("synthetic cubase project".utf8).write(to: archive.appendingPathComponent("Restore Drill.cpr"))
        try Data("synthetic audio".utf8).write(to: archive.appendingPathComponent("Audio/tone.wav"))

        let manifest = try VaultManifestBuilder(fileManager: fileManager).build(at: archive)
        try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: archive, to: staging)
        try VaultManifestBuilder(fileManager: fileManager).verify(manifest, at: staging)
        try fileManager.moveItem(at: staging, to: restored)
        try VaultManifestBuilder(fileManager: fileManager).verify(manifest, at: restored)
        try VaultManifestBuilder(fileManager: fileManager).verify(manifest, at: archive)

        return ProjectVaultRestoreDrillResult(
            completedAt: now(),
            fileCount: manifest.entries.lazy.filter { $0.type == .regularFile }.count,
            archiveCopyPreserved: fileManager.fileExists(atPath: archive.path)
        )
    }
}
