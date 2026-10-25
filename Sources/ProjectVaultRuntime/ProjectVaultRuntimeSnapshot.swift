import Foundation
import NikoMusicCore

public struct ProjectVaultRuntimeSnapshot: Sendable, Equatable {
    public let record: ProjectRecord
    public let transfer: VaultTransferRecord?
    public let restore: VaultRestoreRecord?
    public let linkedArchive: ProjectVaultLinkedArchive?

    public init(
        record: ProjectRecord,
        transfer: VaultTransferRecord?,
        restore: VaultRestoreRecord? = nil,
        linkedArchive: ProjectVaultLinkedArchive? = nil
    ) {
        self.record = record
        self.transfer = transfer
        self.restore = restore
        self.linkedArchive = linkedArchive
    }
}

public struct ProjectVaultLinkedArchive: Sendable, Equatable {
    public let location: ProjectLocation
    public let url: URL

    public init(location: ProjectLocation, url: URL) {
        self.location = location
        self.url = url
    }
}

public extension ProjectVaultRuntimeSnapshot {
    /// The persisted verified terminal transfer, if any. This is evidence that
    /// a verified archive generation exists — never authority to delete. Any
    /// removal still needs a fresh bound confirmation evaluated against live
    /// gates at execution time. Requires a verified terminal state plus a
    /// valid manifest envelope with a matching manifestID and project binding;
    /// generation/source safety stays runtime validated elsewhere.
    var verifiedTerminalTransfer: VaultTransferRecord? {
        guard let transfer,
              VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
              transfer.projectID == record.id,
              let manifestID = transfer.manifestID,
              let manifest = transfer.manifest,
              manifestID == manifest.id,
              (try? manifest.validatePersistedContentEnvelope()) != nil else {
            return nil
        }
        return transfer
    }

    /// Snapshot-backed readiness for a "Ready to free space" offer. All inputs
    /// are persisted evidence plus live location facts: a verified terminal,
    /// a bound generation path, a retained local Active copy, and no Keep
    /// Local pin. Readiness never grants deletion by itself; the offer routes
    /// through a fresh bound confirmation that rechecks every live gate.
    func isReadyToFreeSpace(
        localActiveRetained: Bool,
        isBoundGeneration: Bool,
        isKeepLocal: Bool
    ) -> Bool {
        guard !isKeepLocal, localActiveRetained, isBoundGeneration else {
            return false
        }
        return verifiedTerminalTransfer != nil
    }
}
