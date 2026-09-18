import Foundation

struct ArchiveAccessFailure: Equatable, Sendable {
    var displayName: String
    var reason: String
    var storedRootID: UUID

    var recoveryMessage: String {
        "Niko Music Hub could not open “\(displayName)”. \(reason) Grant access again to scan this folder. Songs already in the catalog stay on disk; they are hidden until access is restored."
    }
}
