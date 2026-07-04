import Foundation

public enum ScanExclusionPolicy {
    public static func terms(from settingsValue: String) -> [String] {
        settingsValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    public static func shouldSkipFolder(named folderName: String, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        let normalized = folderName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return terms.contains { normalized.contains($0) }
    }
}
