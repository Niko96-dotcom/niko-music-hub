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
