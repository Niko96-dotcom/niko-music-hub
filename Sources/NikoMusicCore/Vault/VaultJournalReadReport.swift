import Foundation

/// A Vault journal row whose `record` blob could not be decoded: a damaged blob,
/// or a row written by a newer app version. Only its plain SQL columns are
/// known, so launch recovery reports it and leaves it untouched.
public struct VaultJournalUnreadableRow: Equatable, Hashable, Sendable {
    public enum Journal: String, Sendable {
        case transfers
        case restores
    }

    public var journal: Journal
    public var id: String
    /// The row's `state` (transfers) or `phase` (restores) column as stored.
    public var state: String
    /// The `project_id` column. Only `vault_restores` has one.
    public var projectID: String?
    public var reason: String

    public init(journal: Journal, id: String, state: String, projectID: String? = nil, reason: String) {
        self.journal = journal
        self.id = id
        self.state = state
        self.projectID = projectID
        self.reason = reason
    }
}

/// The readable records of one journal read, plus the rows that could not be
/// decoded. A failed statement or connection still throws instead.
public struct VaultJournalReadReport<Record: Sendable>: Sendable {
    public var records: [Record]
    public var unreadableRows: [VaultJournalUnreadableRow]

    public init(records: [Record], unreadableRows: [VaultJournalUnreadableRow] = []) {
        self.records = records
        self.unreadableRows = unreadableRows
    }
}

extension VaultJournalReadReport: Equatable where Record: Equatable {}
