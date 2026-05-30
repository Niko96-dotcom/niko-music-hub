import Foundation

/// CPR-derived hints so preview ranking tracks the real project version, not orphan demo files.
public struct PreviewRankingProjectContext: Sendable, Equatable {
    public let anchorCPRVersion: Int?
    public let titleTokens: [String]

    public init(anchorCPRVersion: Int?, titleTokens: [String]) {
        self.anchorCPRVersion = anchorCPRVersion
        self.titleTokens = titleTokens
    }

    public static func from(
        projectVersions: [ProjectVersion],
        titleResolver: SongTitleResolver = SongTitleResolver()
    ) -> PreviewRankingProjectContext {
        let anchor = projectVersions.compactMap(\.detectedVersionNumber).max()
        let ranked = projectVersions.sorted { lhs, rhs in
            let lv = lhs.detectedVersionNumber ?? 0
            let rv = rhs.detectedVersionNumber ?? 0
            if lv != rv { return lv > rv }
            return lhs.modifiedAt > rhs.modifiedAt
        }
        let tokens: [String]
        if let fileName = ranked.first?.fileName,
           let title = titleResolver.titleFromCPRFileName(fileName) {
            tokens = Self.tokens(fromTitle: title)
        } else {
            tokens = []
        }
        return PreviewRankingProjectContext(anchorCPRVersion: anchor, titleTokens: tokens)
    }

    static func tokens(fromTitle title: String) -> [String] {
        title
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !$0.allSatisfy(\.isNumber) }
    }
}
