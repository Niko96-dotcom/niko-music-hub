import Foundation
import NikoMusicCore

/// Filters the ranked list without changing candidate identity or selection.
enum ArchivePreviewCandidateFilter {
    static func candidates(_ candidates: [PreviewCandidate], matching query: String) -> [PreviewCandidate] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return candidates }
        return candidates.filter { candidate in
            terms.allSatisfy {
                candidate.fileName.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// Use the full list so labels remain stable while filtering or paging.
    static func folderLabels(for candidates: [PreviewCandidate], relativeTo root: URL) -> [String: String] {
        let groups = Dictionary(grouping: candidates) {
            $0.fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let rootParts = root.standardizedFileURL.pathComponents
        var labels: [String: String] = [:]
        for group in groups.values where group.count > 1 {
            for candidate in group {
                let folder = candidate.filePath.deletingLastPathComponent().standardizedFileURL
                let parts = folder.pathComponents
                if parts.starts(with: rootParts) {
                    let relative = parts.dropFirst(rootParts.count).joined(separator: "/")
                    labels[candidate.id] = relative.isEmpty ? "Project folder" : relative
                } else {
                    labels[candidate.id] = folder.path
                }
            }
        }
        return labels
    }
}
