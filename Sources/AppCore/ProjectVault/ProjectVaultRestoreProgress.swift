import Foundation
import NikoMusicCore

/// Observed work only: totals describe the restore, not a fabricated completion percentage.
public struct ProjectVaultRestoreProgress: Equatable, Sendable {
    public let phase: VaultRestorePhase
    public let totalBytes: Int64?
    public let fileCount: Int?

    public init(phase: VaultRestorePhase, manifest: VaultManifest? = nil) {
        self.phase = phase
        totalBytes = manifest?.totalBytes
        fileCount = manifest?.entries.filter { $0.type == .regularFile }.count
    }

    public var title: String {
        switch phase {
        case .materializingArchive: "Checking and downloading archive files"
        case .copyingToActiveStaging: "Copying to Active Projects"
        case .verifyingActiveStaging: "Verifying restored files"
        case .promotingActiveCopy, .persistingActiveLocation: "Finishing the restored copy"
        case .openingInCubase: "Opening in the DAW"
        case .superseded: "Restore superseded"
        }
    }

    public var scopeDescription: String? {
        guard let totalBytes, let fileCount else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(fileCount) \(fileCount == 1 ? "file" : "files") · \(size) total"
    }
}
