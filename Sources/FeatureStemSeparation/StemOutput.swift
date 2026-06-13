import Foundation

public struct StemOutput: Equatable, Sendable, Identifiable {
    public let role: StemRole
    public let fileURL: URL

    public init(role: StemRole, fileURL: URL) {
        self.role = role
        self.fileURL = fileURL
    }

    public var id: String { role.rawValue }
}
