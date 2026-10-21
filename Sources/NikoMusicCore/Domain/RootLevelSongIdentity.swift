import Foundation

/// Loose project versions share an identity; their opening path still names the latest file.
/// The same filename grouping is used by scanning and by legacy metadata migration.
public enum RootLevelSongIdentity {
    // This grouping is part of the persisted key grammar; changing it requires a key migration.
    static func groupKey(for version: ProjectVersion) -> String {
        let title = SongTitleResolver().bestTitle(from: [version])
            ?? (version.fileName as NSString).deletingPathExtension
        return title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func id(forProjectFile file: URL) -> String? {
        guard file.isFileURL, ProjectFileFormat(url: file) != nil else { return nil }
        let version = ProjectVersion(filePath: file, fileName: file.lastPathComponent, modifiedAt: .distantPast)
        let root = file.deletingLastPathComponent().standardizedFileURL.absoluteString
        let key = Data(groupKey(for: version).utf8).base64EncodedString()
        return "loose-project:\(root)#\(key)"
    }

    static func songID(folderPath: URL, versions: [ProjectVersion]) -> String {
        let path = folderPath.standardizedFileURL.path
        // Almost every song is a folder: avoid walking its versions to decide that.
        guard let id = id(forProjectFile: folderPath),
              versions.contains(where: { $0.filePath.standardizedFileURL.path == path }) else { return path }
        return id
    }
}
