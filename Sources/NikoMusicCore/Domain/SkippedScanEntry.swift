import Foundation

public enum SkippedScanEntryKind: String, Sendable, Codable, Equatable {
    case nonFolderAtRoot
    case invalidRoot
}

public struct SkippedScanEntry: Sendable, Equatable, Codable {
    /// Shared scanner copy for root-level files; skipped search ignores reason-only hits on this text.
    public static let standardNonFolderAtRootReason =
        "Not a folder — only immediate child folders are scanned as songs"

    public let kind: SkippedScanEntryKind
    public let label: String
    public let reason: String

    public init(kind: SkippedScanEntryKind, label: String, reason: String) {
        self.kind = kind
        self.label = label
        self.reason = reason
    }
}
