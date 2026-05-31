import Foundation

public struct CPRVersionDetector: @unchecked Sendable {
    private static let supportedExtension = "cpr"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectImmediateVersions(in folder: URL) throws -> [ProjectVersion] {
        let children = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var versions: [ProjectVersion] = []
        for child in children {
            if let version = try projectVersionIfSupported(at: child) {
                versions.append(version)
            }
        }
        return versions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func detectVersions(in songFolder: URL) throws -> [ProjectVersion] {
        guard let enumerator = fileManager.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var versions: [ProjectVersion] = []
        for case let fileURL as URL in enumerator {
            if let version = try projectVersionIfSupported(at: fileURL) {
                versions.append(version)
            }
        }

        return versions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func latestCPR(from versions: [ProjectVersion]) -> ProjectVersion? {
        versions.max(by: { $0.modifiedAt < $1.modifiedAt })
    }

    private func projectVersionIfSupported(at fileURL: URL) throws -> ProjectVersion? {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == Self.supportedExtension else { return nil }
        let name = fileURL.lastPathComponent.lowercased()
        if name.hasSuffix(".bak.cpr") || name.contains(".bak.") {
            return nil
        }

        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true else { return nil }
        let modified = values.contentModificationDate ?? .distantPast
        let versionNumber = Self.parseVersionNumber(from: fileURL.lastPathComponent)
        return ProjectVersion(
            filePath: fileURL,
            fileName: fileURL.lastPathComponent,
            modifiedAt: modified,
            detectedVersionNumber: versionNumber
        )
    }

    static func parseVersionNumber(from fileName: String) -> Int? {
        let stem = fileName
            .replacingOccurrences(of: ".cpr", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = stem.split { $0 == " " || $0 == "_" || $0 == "-" }.map(String.init)
        for part in parts.reversed() {
            let digits = part.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if let value = Int(digits), value > 0 {
                return value
            }
        }
        return nil
    }
}
