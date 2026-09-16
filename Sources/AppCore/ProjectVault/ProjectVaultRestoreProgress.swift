import Foundation
import NikoMusicCore

/// Observed work only: totals describe the restore, not a fabricated completion percentage.
/// NMH-054: `copiedBytes` is measured from disk (staging); `fraction` is nil when
/// totals are unknown so callers stay indeterminate or show a phase checklist.
public struct ProjectVaultRestoreProgress: Equatable, Sendable {
    public let phase: VaultRestorePhase
    public let totalBytes: Int64?
    public let fileCount: Int?
    public let copiedBytes: Int64?

    public init(phase: VaultRestorePhase, manifest: VaultManifest? = nil, copiedBytes: Int64? = nil) {
        self.phase = phase
        totalBytes = manifest?.totalBytes
        fileCount = manifest?.entries.filter { $0.type == .regularFile }.count
        self.copiedBytes = copiedBytes
    }

    public init(phase: VaultRestorePhase, totalBytes: Int64?, fileCount: Int?, copiedBytes: Int64? = nil) {
        self.phase = phase
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.copiedBytes = copiedBytes
    }

    /// Honest 0…1 fraction, or nil when totals are unknown. Clamped; never
    /// animates to 100% on its own — callers must not fake completion before verify.
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        let copied = copiedBytes ?? 0
        return min(max(Double(copied) / Double(totalBytes), 0), 1)
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

    /// NMH-054 fallback when byte size cannot be read: one step per phase
    /// except `.superseded`, in restore order.
    public static var checklistPhases: [VaultRestorePhase] {
        [.materializingArchive, .copyingToActiveStaging, .verifyingActiveStaging,
         .promotingActiveCopy, .persistingActiveLocation, .openingInCubase]
    }

    /// Position of `phase` within `checklistPhases`, or nil for `.superseded`.
    public var checklistIndex: Int? {
        Self.checklistPhases.firstIndex(of: phase)
    }
}
