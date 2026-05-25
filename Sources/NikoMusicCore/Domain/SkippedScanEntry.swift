import Foundation

public enum SkippedScanEntryKind: String, Sendable, Codable, Equatable {
    case nonFolderAtRoot
    case invalidRoot
}

public struct SkippedScanEntry: Sendable, Equatable, Codable {
    public let kind: SkippedScanEntryKind
    public let label: String
    public let reason: String

    public init(kind: SkippedScanEntryKind, label: String, reason: String) {
        self.kind = kind
        self.label = label
        self.reason = reason
    }
}
