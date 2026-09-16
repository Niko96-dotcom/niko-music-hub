import AppKit
import Foundation
import UniformTypeIdentifiers

enum ArchiveExportPaths {
    /// NMH-055: user-facing export kinds with their Save panel configuration.
    enum ExportKind {
        case index
        case scanDiagnostics

        var allowedContentTypes: [UTType] {
            switch self {
            case .index: [.json]
            case .scanDiagnostics: [.plainText]
            }
        }

        func defaultFilename(for date: Date = Date()) -> String {
            switch self {
            case .index: ArchiveExportPaths.indexFilename(for: date)
            case .scanDiagnostics: ArchiveExportPaths.scanDiagnosticsFilename(for: date)
            }
        }

        var saveMessage: String {
            switch self {
            case .index: "Choose where to save the archive index."
            case .scanDiagnostics: "Choose where to save scan diagnostics."
            }
        }
    }

    /// Calendar-day stamp (`yyyy-MM-dd`) in the person's local time zone.
    static func exportDateStamp(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func indexFilename(for date: Date = Date()) -> String {
        "archive-index-\(exportDateStamp(for: date)).json"
    }

    static func scanDiagnosticsFilename(for date: Date = Date()) -> String {
        "scan-diagnostics-\(exportDateStamp(for: date)).txt"
    }

    /// Save-panel starting folder: the app output folder, else the person's Documents.
    static func defaultDirectory(outputFolderURL: URL?) -> URL {
        if let outputFolderURL { return outputFolderURL }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// NMH-055: presents the system Save panel for a user-facing export.
    /// Returns the chosen destination, or `nil` when the person cancels.
    @MainActor
    static func runSavePanel(
        for kind: ExportKind,
        directoryURL: URL?
    ) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = kind.allowedContentTypes
        panel.nameFieldStringValue = kind.defaultFilename()
        panel.prompt = "Export"
        panel.message = kind.saveMessage
        panel.directoryURL = defaultDirectory(outputFolderURL: directoryURL)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

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
