import Foundation

/// An explicit, freshly observed location for an already known identity.
/// Linking records location evidence; it does not certify archive content or create a transfer.
public struct ProjectCatalogArchiveLink: Sendable {
    public let projectID: ProjectID
    public let location: ProjectLocation
    public let evidence: ProjectIdentityEvidence

    public init(projectID: ProjectID, location: ProjectLocation, evidence: ProjectIdentityEvidence) {
        self.projectID = projectID
        self.location = location
        self.evidence = evidence
    }
}
