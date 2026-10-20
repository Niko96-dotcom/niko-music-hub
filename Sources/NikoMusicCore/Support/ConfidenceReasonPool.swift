import Foundation

/// One shared copy of each distinct list of preview confidence reasons.
///
/// A candidate's reasons are a handful of short tokens ("folder:mixdown", "role:full-mix", "recency") and almost
/// every candidate of an archive carries one of a few hundred combinations. Decoded or ranked separately, each
/// candidate owns its own array and its own string objects: for 10,000 songs that is about 40 MB of identical
/// text. Arrays are values, so sharing one canonical array changes nothing a caller can observe.
final class ConfidenceReasonPool: @unchecked Sendable {
    static let shared = ConfidenceReasonPool()

    /// Distinct lists kept at most; past it, new lists are returned as they came (still correct, just unshared).
    private static let capacity = 20_000

    private let lock = NSLock()
    private var canonicalByReasons: [[String]: [String]] = [:]

    func canonical(_ reasons: [String]) -> [String] {
        guard !reasons.isEmpty else { return reasons }
        return lock.withLock {
            if let shared = canonicalByReasons[reasons] { return shared }
            if canonicalByReasons.count < Self.capacity { canonicalByReasons[reasons] = reasons }
            return reasons
        }
    }
}
