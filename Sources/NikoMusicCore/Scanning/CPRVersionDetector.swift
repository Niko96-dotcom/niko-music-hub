import Foundation

public struct CPRVersionDetector: @unchecked Sendable {
    private static let supportedExtension = "cpr"
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
            let ext = fileURL.pathExtension.lowercased()
            guard ext == Self.supportedExtension else { continue }
            let name = fileURL.lastPathComponent.lowercased()
            if name.hasSuffix(".bak.cpr") || name.contains(".bak.") {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            let versionNumber = Self.parseVersionNumber(from: fileURL.lastPathComponent)
            versions.append(
                ProjectVersion(
                    filePath: fileURL,
                    fileName: fileURL.lastPathComponent,
                    modifiedAt: modified,
                    detectedVersionNumber: versionNumber
                )
            )
        }

        return versions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func latestCPR(from versions: [ProjectVersion]) -> ProjectVersion? {
        versions.max(by: { $0.modifiedAt < $1.modifiedAt })
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
