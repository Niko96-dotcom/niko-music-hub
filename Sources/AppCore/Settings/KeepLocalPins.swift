import Foundation
import NikoMusicCore

/// Keep Local pins: projects the person keeps on this Mac. The Project Vault
/// never removes a pinned project's Active folder.
///
/// The stored keys mix catalog project IDs, song IDs and folder paths in
/// several spellings, because older builds wrote and compared spellings
/// (ADR 021). They are private to this type: callers describe a project with
/// what they know, and matching, writing, removing and the stored form stay
/// here. Settings store the value under the old key, `keepLocalProjectIDs`, as
/// the same array of strings.
public struct KeepLocalPins: Equatable, Sendable {
    /// One project as a caller knows it. IDs match exactly; folders match by
    /// canonical folder path, so another spelling of the same folder counts.
    public struct Project: Equatable, Sendable {
        let ids: Set<String>
        let folders: [URL]

        public init(projectIDs: [ProjectID] = [], songIDs: [String] = [], folders: [URL] = []) {
            ids = Set(projectIDs.map(\.description)).union(songIDs)
            self.folders = folders
        }
    }

    /// What settings store. Only this type reads or builds it (ADR 021).
    private var storedKeys: Set<String>
    /// Canonical folder paths of the stored path keys, computed once per value
    /// so a check canonicalizes only the caller's folders.
    private var storedFolderPaths: Set<String>

    /// No pins.
    public init() {
        self.init(storedKeys: [])
    }

    private init(storedKeys: Set<String>) {
        self.storedKeys = storedKeys
        storedFolderPaths = Self.canonicalFolderPaths(ofKeys: storedKeys)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storedKeys == rhs.storedKeys
    }

    /// The number of stored keys, not of projects: one pin writes several
    /// spellings, and an older pin cannot be grouped by project (ADR 021).
    /// Diagnostics and the Review Keep Local count show it.
    public var storedKeyCount: Int {
        storedKeys.count
    }

    /// An ID-only project, or a set without path keys, needs no filesystem call.
    public func contains(_ project: Project) -> Bool {
        if !storedKeys.isDisjoint(with: project.ids) { return true }
        guard !storedFolderPaths.isEmpty else { return false }
        return project.folders.contains { storedFolderPaths.contains(Self.canonicalFolderPath($0)) }
    }

    /// Writes the IDs and, per folder, the raw, standardized, resolved and
    /// canonical spellings: every spelling an older build compares.
    public mutating func pin(_ project: Project) {
        storedKeys.formUnion(project.ids)
        for folder in project.folders {
            let standardized = folder.standardizedFileURL
            let canonical = Self.canonicalFolderPath(folder)
            storedKeys.formUnion([
                folder.path,
                standardized.path,
                standardized.resolvingSymlinksInPath().path,
                canonical,
            ])
            storedFolderPaths.insert(canonical)
        }
    }

    /// Removes the IDs and every stored path with the same canonical folder
    /// path, whatever spelling wrote it (a symlinked root, a `/private` alias).
    public mutating func unpin(_ project: Project) {
        let folders = Set(project.folders.map(Self.canonicalFolderPath))
        storedKeys = storedKeys.filter { key in
            !project.ids.contains(key)
                && !(Self.isPathKey(key) && folders.contains(Self.canonicalFolderPath(ofKey: key)))
        }
        storedFolderPaths = Self.canonicalFolderPaths(ofKeys: storedKeys)
    }

    /// The folder identity Keep Local and the archive browser compare:
    /// standardized, symlinks resolved, and the `/private/var` and
    /// `/private/tmp` aliases shortened even for a path that does not exist.
    public static func canonicalFolderPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    private static func isPathKey(_ key: String) -> Bool {
        key.hasPrefix("/")
    }

    private static func canonicalFolderPath(ofKey key: String) -> String {
        canonicalFolderPath(URL(fileURLWithPath: key, isDirectory: true))
    }

    private static func canonicalFolderPaths(ofKeys keys: Set<String>) -> Set<String> {
        Set(keys.filter(isPathKey).map(canonicalFolderPath(ofKey:)))
    }
}

/// The stored form older builds read and write: a plain array of the keys.
extension KeepLocalPins: Codable {
    public init(from decoder: Decoder) throws {
        self.init(storedKeys: try decoder.singleValueContainer().decode(Set<String>.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedKeys)
    }
}

extension KeepLocalPins {
    /// Settings repair for a stored value that did not decode: keeps every
    /// readable key. `isComplete` is false when the value was not an array or
    /// held an entry that is not a string, so some pins may be missing.
    static func salvaging(storedValue: Any) -> (pins: KeepLocalPins, isComplete: Bool) {
        let entries = storedValue as? [Any]
        let keys = entries?.compactMap { $0 as? String } ?? []
        return (KeepLocalPins(storedKeys: Set(keys)), entries != nil && keys.count == entries?.count)
    }
}
