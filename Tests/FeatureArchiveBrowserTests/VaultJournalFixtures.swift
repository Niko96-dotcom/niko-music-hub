import Foundation
import NikoMusicCore

/// Vault records in a state a journal row holds. A live record changes its state only through
/// `apply(_:)` and its phase only through `changePhase(to:)`, which check the tables; a fixture that
/// starts elsewhere is planted the way the store reads a row, through the decoding initializer.
extension VaultTransferRecord {
    init(
        id: UUID = UUID(),
        projectID: ProjectID,
        sourceURL: URL,
        stagingURL: URL,
        destinationURL: URL,
        state: VaultTransferState,
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            projectID: projectID,
            sourceURL: sourceURL,
            stagingURL: stagingURL,
            destinationURL: destinationURL,
            createdAt: createdAt
        )
        plantJournalState(state)
    }

    mutating func plantJournalState(_ state: VaultTransferState) {
        self = VaultJournalRow.decoded(self, setting: "state", to: state.rawValue)
    }
}

extension VaultRestoreRecord {
    init(
        id: UUID = UUID(),
        projectID: ProjectID,
        archiveGenerationURL: URL,
        stagingURL: URL,
        destinationURL: URL,
        manifest: VaultManifest,
        selectedProjectRelativePath: String? = nil,
        linkedArchiveLocation: ProjectLocation? = nil,
        archiveTransferID: UUID? = nil,
        archiveTransferState: VaultTransferState? = nil,
        requiresArchiveMaterialization: Bool = true,
        projectionSupplement: VaultProjectionSupplement? = nil,
        phase: VaultRestorePhase,
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            projectID: projectID,
            archiveGenerationURL: archiveGenerationURL,
            stagingURL: stagingURL,
            destinationURL: destinationURL,
            manifest: manifest,
            selectedProjectRelativePath: selectedProjectRelativePath,
            linkedArchiveLocation: linkedArchiveLocation,
            archiveTransferID: archiveTransferID,
            archiveTransferState: archiveTransferState,
            requiresArchiveMaterialization: requiresArchiveMaterialization,
            projectionSupplement: projectionSupplement,
            createdAt: createdAt
        )
        plantJournalPhase(phase)
    }

    mutating func plantJournalPhase(_ phase: VaultRestorePhase) {
        self = VaultJournalRow.decoded(self, setting: "phase", to: phase.rawValue)
    }
}

/// Encodes a record, replaces one field and decodes it again. A binary property list keeps every
/// date and number exact, so the planted record equals the original in all other fields.
private enum VaultJournalRow {
    static func decoded<Record: Codable>(_ record: Record, setting key: String, to value: String) -> Record {
        do {
            let encoded = try PropertyListEncoder().encode(record)
            guard var row = try PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any] else {
                preconditionFailure("a Vault record encodes as a keyed row")
            }
            row[key] = value
            let planted = try PropertyListSerialization.data(fromPropertyList: row, format: .binary, options: 0)
            return try PropertyListDecoder().decode(Record.self, from: planted)
        } catch {
            preconditionFailure("planting \(key) = \(value) failed: \(error)")
        }
    }
}
