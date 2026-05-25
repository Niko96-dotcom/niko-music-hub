import Foundation

public struct PreviewCandidateDetector: @unchecked Sendable {
    private static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aiff", "aif", "flac"]
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func detectCandidates(in songFolder: URL) throws -> [PreviewCandidate] {
        guard let enumerator = fileManager.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [PreviewCandidate] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard Self.audioExtensions.contains(ext) else { continue }

            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            let role = Self.folderRole(for: fileURL, songFolder: songFolder)
            let detectedRole = Self.detectedRole(from: fileURL.lastPathComponent)
            candidates.append(
                PreviewCandidate(
                    filePath: fileURL,
                    fileName: fileURL.lastPathComponent,
                    folderRole: role,
                    modifiedAt: modified,
                    detectedRole: detectedRole
                )
            )
        }
        return candidates
    }

    static func folderRole(for fileURL: URL, songFolder: URL) -> PreviewFolderRole {
        let relative = fileURL.deletingLastPathComponent().path
            .replacingOccurrences(of: songFolder.standardizedFileURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/").map(String.init)
        guard let first = components.first?.lowercased() else { return .root }
        switch first {
        case "mixdown": return .mixdown
        case "stems": return .stems
        default:
            return components.isEmpty ? .root : .other
        }
    }

    static func detectedRole(from fileName: String) -> PreviewDetectedRole {
        let lower = fileName.lowercased()
        if lower.contains("instr") || lower.contains("instrumental") { return .instrumental }
        if lower.contains("acapella") || lower.contains("vox only") { return .acapella }
        if lower.contains("stem") { return .stems }
        if lower.contains("master") { return .master }
        if lower.contains("mixdown") || lower.contains(" mix") || lower.contains("bounce") || lower.contains("preview") {
            return .mainMix
        }
        return .unknown
    }
}
