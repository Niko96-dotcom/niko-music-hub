import Foundation

enum ArchiveExportPaths {
    static func stampedFileURL(
        subdirectory: String,
        namePrefix: String,
        nameSuffix: String = ""
    ) throws -> URL {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return exportDir.appendingPathComponent("\(namePrefix)-\(stamp)\(nameSuffix)")
    }
}
