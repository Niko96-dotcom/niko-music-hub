import Foundation

/// How many song folders a full scan may walk at once.
///
/// The limit is the smaller of two numbers: what the archive root's volume handles well, and the
/// caller's budget. A spinning or network disk turns parallel folder walks into seeks and round trips,
/// so its limit is low; the Mac's internal SSD takes the full budget. A scan someone waits for (started
/// by the user, or a first scan with an empty board) gets the interactive budget; a rescan behind cached
/// songs that are already on screen takes half of it.
public enum ScanWorkerBudget: Sendable, Equatable {
    case interactive
    case background

    public var maximumWorkers: Int {
        switch self {
        case .interactive: 8
        case .background: 4
        }
    }

    /// Network volumes: 2. Other external volumes (USB/Thunderbolt disks, often spinning): 4.
    /// Internal volumes: 8. Unknown: 4. Foundation cannot tell a spinning disk from an SSD, so
    /// external disks get the cautious limit.
    public static func volumeLimit(for root: URL) -> Int {
        let values = try? root.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey])
        if values?.volumeIsLocal == false { return 2 }
        if values?.volumeIsInternal == true { return 8 }
        return 4
    }
}
