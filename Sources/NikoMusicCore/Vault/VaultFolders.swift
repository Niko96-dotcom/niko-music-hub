import Foundation

/// The folders the app keeps inside the two Project Vault roots. They are an
/// on-disk format: Vaults made by earlier versions must stay readable, so the
/// names and the nesting never change.
///
///     Archive root  generations/<project>/generation-<transfer>   verified copies
///                   .niko-staging/<project>/<transfer>             an archive in progress
///     Active root   .niko-staging/<project>/<restore>              a restore in progress
///                   .niko-recovery/<transfer>/<attempt>/<folder>   copies set aside by recovery
///
/// Project and operation IDs are lowercased UUIDs. Callers keep their own
/// containment and symlink checks; this type only says where the folders are
/// and which names are reserved.
public enum VaultFolders {
    private static let stagingName = ".niko-staging"
    private static let generationsName = "generations"
    private static let recoveryName = ".niko-recovery"
    private static let reservedActivePrefix = ".niko-"

    /// The staging folder of a root: archives stage in the Archive root,
    /// restores in the Active root.
    public static func staging(in root: URL) -> URL {
        root.appendingPathComponent(stagingName, isDirectory: true)
    }

    /// Where one archive (`operationID` = transfer) or restore (`operationID` =
    /// restore) stages its copy.
    public static func staging(in root: URL, projectID: ProjectID, operationID: UUID) -> URL {
        staging(in: root)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(operationID.uuidString.lowercased(), isDirectory: true)
    }

    public static func generations(in archiveRoot: URL) -> URL {
        archiveRoot.appendingPathComponent(generationsName, isDirectory: true)
    }

    /// The verified copy a transfer writes; the only place it may be.
    public static func generation(in archiveRoot: URL, projectID: ProjectID, transferID: UUID) -> URL {
        generations(in: archiveRoot)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(generationFolderName(transferID: transferID), isDirectory: true)
    }

    public static func generationFolderName(transferID: UUID) -> String {
        "generation-\(transferID.uuidString.lowercased())"
    }

    /// Everything recovery set aside for one transfer.
    public static func recovery(in activeRoot: URL, transferID: UUID) -> URL {
        activeRoot
            .appendingPathComponent(recoveryName, isDirectory: true)
            .appendingPathComponent(transferID.uuidString.lowercased(), isDirectory: true)
    }

    /// A new place to set aside a surviving Active folder: a fresh attempt
    /// folder per call, so an earlier attempt is never overwritten.
    public static func preservedActiveCopy(in activeRoot: URL, transferID: UUID, folderName: String) -> URL {
        recovery(in: activeRoot, transferID: transferID)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// `generations` and `.niko-staging`, case-insensitive: never an ordinary
    /// (catalog-linked) archive folder at the top of the Archive root.
    public static func isReservedInArchiveRoot(_ name: String) -> Bool {
        [generationsName, stagingName].contains(name.lowercased())
    }

    /// Any `.niko-` name (staging, recovery and any later app folder): never a
    /// restore destination or part of one.
    public static func isReservedInActiveRoot(_ component: String) -> Bool {
        component.hasPrefix(reservedActivePrefix)
    }
}
