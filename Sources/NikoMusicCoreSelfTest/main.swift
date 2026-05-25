import Foundation
import NikoMusicCore

struct CLIOptions {
    var fixtureRoot: URL?
    var realRoot: URL?
    var readOnly: Bool
}

func parseOptions() -> CLIOptions {
    var fixtureRoot: URL?
    var realRoot: URL?
    var readOnly = false
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.first {
        args = args.dropFirst()
        switch arg {
        case "--fixture-root":
            if let path = args.first {
                args = args.dropFirst()
                fixtureRoot = URL(fileURLWithPath: path, isDirectory: true)
            }
        case "--real-root":
            if let path = args.first {
                args = args.dropFirst()
                realRoot = URL(fileURLWithPath: path, isDirectory: true)
            }
        case "--read-only":
            readOnly = true
        default:
            break
        }
    }
    return CLIOptions(fixtureRoot: fixtureRoot, realRoot: realRoot, readOnly: readOnly)
}

func defaultFixtureRoot() -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return cwd.appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
}

@main
struct NikoMusicCoreSelfTest {
    static func main() throws {
        let options = parseOptions()
        let roots: [URL]
        if let real = options.realRoot {
            roots = [real]
            if options.readOnly {
                let policy = ReadOnlyArchivePolicy()
                guard policy.writeProbeDenied(under: real) else {
                    fputs("read-only policy failed: writes would be allowed under \(real.path)\n", stderr)
                    exit(1)
                }
            }
        } else {
            roots = [options.fixtureRoot ?? defaultFixtureRoot()]
        }

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: roots)
        let index = MusicSearchIndex(songs: result.songs)
        let neonMatches = index.search("Neon Hook")

        print("roots=\(roots.map(\.path).joined(separator: ","))")
        print("songs=\(result.songs.count)")
        print("warnings=\(result.globalWarnings.count)")
        print("skipped=\(result.skippedEntries.count)")
        print("neon_hook_matches=\(neonMatches.count)")

        for song in result.songs {
            let cprCount = song.projectVersions.count
            let previewCount = song.previewCandidates.count
            let mainPreview = song.mainPreviewCandidateID ?? "none"
            let latest = song.latestCPR?.fileName ?? "none"
            print("song=\(song.displayTitle) cpr=\(cprCount) previews=\(previewCount) main_preview=\(mainPreview) latest_cpr=\(latest)")
        }
    }
}
