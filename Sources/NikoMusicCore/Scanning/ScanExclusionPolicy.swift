import Foundation

public enum ScanExclusionPolicy {
    private static let foldLocale = Locale(identifier: "en_US_POSIX")

    static func folded(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: foldLocale)
            .lowercased()
    }

    public static func terms(from settingsValue: String) -> [String] {
        settingsValue
            .split(separator: ",")
            .map { folded($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    public static func shouldSkipFolder(named folderName: String, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        let normalized = folded(folderName)
        return terms.contains {
            let term = folded($0)
            guard !term.isEmpty else { return false }
            return normalized.contains(term)
        }
    }
}
