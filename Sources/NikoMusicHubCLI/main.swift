import Foundation
import NikoMusicCore

@main
struct NikoMusicHubCLI {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(1)
        }
        args.removeFirst()

        // An error that escapes `@main` traps the process ("Error raised at
        // top level"), so every failure is reported here and ends in exit 1.
        do {
            switch command {
            case "export-index":
                try runExportIndex(args: args)
            case "export-diagnostics":
                try runExportDiagnostics(args: args)
            case "--help", "-h", "help":
                printUsage()
            default:
                fputs("unknown command: \(command)\n", stderr)
                printUsage()
                exit(1)
            }
        } catch {
            fputs("error: \(errorMessage(error))\n", stderr)
            exit(1)
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        switch error {
        case let error as ArchiveDiagnosticsExportError:
            switch error {
            case .destinationInsideArchiveRoot:
                return "the output location is inside an archive root. Choose a path outside the archive."
            }
        case let error as CLIError:
            return error.description
        default:
            return error.localizedDescription
        }
    }

    private static func printUsage() {
        print(
            """
            NikoMusicHubCLI
              export-index --roots <path> [--output <file>]
              export-diagnostics --roots <path> [--output <file>]
            """
        )
    }

    private static func runExportIndex(args: [String]) throws {
        let roots = try parseRoots(args)
        let output = parseOutput(args) ?? URL(fileURLWithPath: "archive-index-export.json")
        // Same read-only boundary as the app's export and `export-diagnostics`:
        // never write the index into an archive root.
        let policy = ReadOnlyArchivePolicy()
        do {
            try policy.enforceNoWrite(at: output, archiveRoots: roots)
            try policy.enforceNoWrite(at: output.deletingLastPathComponent(), archiveRoots: roots)
        } catch ReadOnlyArchivePolicyError.writeDenied {
            throw ArchiveDiagnosticsExportError.destinationInsideArchiveRoot
        }
        let result = try MusicArchiveScanner().scan(roots: roots)
        let data = try ArchiveIndexExporter.exportJSON(roots: roots, songs: result.songs)
        // Atomic like `export-diagnostics`: an interrupted write must not
        // leave a truncated index in place of an earlier good export.
        try data.write(to: output, options: .atomic)
        print(output.path)
    }

    private static func runExportDiagnostics(args: [String]) throws {
        let roots = try parseRoots(args)
        let output = parseOutput(args) ?? URL(fileURLWithPath: "archive-diagnostics-export.txt")
        let result = try MusicArchiveScanner().scan(roots: roots)
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(result: result, roots: roots)
        let report = ArchiveIntelligence.missingAudioReport(songs: result.songs)
        try ArchiveDiagnosticsExporter.exportText(
            diagnostics: diagnostics,
            to: output,
            archiveRoots: roots,
            orphanAudioReport: report
        )
        print(output.path)
    }

    private static func parseRoots(_ args: [String]) throws -> [URL] {
        var roots: [URL] = []
        var index = 0
        while index < args.count {
            if args[index] == "--roots", index + 1 < args.count {
                roots.append(URL(fileURLWithPath: args[index + 1], isDirectory: true))
                index += 2
            } else {
                index += 1
            }
        }
        guard !roots.isEmpty else {
            throw CLIError.missingRoots
        }
        return roots
    }

    private static func parseOutput(_ args: [String]) -> URL? {
        var index = 0
        while index < args.count {
            if args[index] == "--output", index + 1 < args.count {
                return URL(fileURLWithPath: args[index + 1])
            }
            index += 1
        }
        return nil
    }

    private enum CLIError: Error, CustomStringConvertible {
        case missingRoots

        var description: String {
            switch self {
            case .missingRoots: "--roots is required"
            }
        }
    }
}
