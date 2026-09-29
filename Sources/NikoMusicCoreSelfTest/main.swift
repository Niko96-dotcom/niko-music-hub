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

/// Facts about `Fixtures/CubaseArchive` written down by hand from
/// `script/fixtures/generate_cubase_archive_fixtures.sh`, deliberately not computed by the scanner.
/// Update them together with the generator.
enum FixtureExpectations {
    /// 8 song folders with a CPR (Neon Hook, Second Song, Preview Ranking Lab, three Equal Score
    /// folders, 90s Rave, Amber Moth) + "Broken Folder Example" (notes only, no CPR).
    static let songCount = 9
    /// Root-level LOOSE_FILE.txt and the generated README.md.
    static let skippedCount = 2
    static let skippedLabels: Set<String> = ["LOOSE_FILE.txt", "README.md"]
    /// Neon Hook.cpr is given a newer mtime than "Neon Hook v2.cpr"; the full mix "Neon Hook v3.wav"
    /// beats "Neon Hook instr.wav".
    static let neonHookLatestCPR = "Neon Hook.cpr"
    static let neonHookMainPreviewSuffix = "/Neon Hook/Mixdown/Neon Hook v3.wav"
    /// The newest file in Amber Moth is the drum stem; the master mix must still win.
    static let amberMothMainPreviewSuffix = "/Amber Moth/Mixdown/Amber Moth master mix.wav"
    /// Notes-only folder: a song row with no project and no preview.
    static let brokenFolderTitle = "Broken Folder Example"
}

func verifyFixtureExpectations(result: ScanResult, neonMatches: [Song]) -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { failures.append(message()) }
    }

    check(result.songs.count == FixtureExpectations.songCount,
          "song count \(result.songs.count) != \(FixtureExpectations.songCount)")
    check(result.skippedEntries.count == FixtureExpectations.skippedCount,
          "skipped count \(result.skippedEntries.count) != \(FixtureExpectations.skippedCount)")
    check(Set(result.skippedEntries.map(\.label)) == FixtureExpectations.skippedLabels,
          "skipped labels \(result.skippedEntries.map(\.label).sorted()) != \(FixtureExpectations.skippedLabels.sorted())")

    let neon = result.songs.first { $0.displayTitle == "Neon Hook" }
    check(neon != nil, "Neon Hook song missing")
    if let neon {
        check(neon.latestCPR?.fileName == FixtureExpectations.neonHookLatestCPR,
              "Neon Hook latest CPR \(neon.latestCPR?.fileName ?? "none") != \(FixtureExpectations.neonHookLatestCPR)")
        check(neon.mainPreviewCandidateID?.hasSuffix(FixtureExpectations.neonHookMainPreviewSuffix) == true,
              "Neon Hook main preview \(neon.mainPreviewCandidateID ?? "none") does not end with \(FixtureExpectations.neonHookMainPreviewSuffix)")
    }

    let amber = result.songs.first { $0.displayTitle == "Amber Moth" }
    check(amber != nil, "Amber Moth song missing")
    if let amber {
        check(amber.mainPreviewCandidateID?.hasSuffix(FixtureExpectations.amberMothMainPreviewSuffix) == true,
              "Amber Moth main preview \(amber.mainPreviewCandidateID ?? "none") does not end with \(FixtureExpectations.amberMothMainPreviewSuffix)")
    }

    let broken = result.songs.first { $0.displayTitle == FixtureExpectations.brokenFolderTitle }
    check(broken != nil, "\(FixtureExpectations.brokenFolderTitle) song missing")
    if let broken {
        check(broken.latestCPR == nil && broken.mainPreviewCandidateID == nil,
              "\(FixtureExpectations.brokenFolderTitle) unexpectedly has a project or preview")
    }

    check(neonMatches.count == 1, "search \"Neon Hook\" returned \(neonMatches.count) matches, expected exactly 1")
    check(neonMatches.first?.displayTitle == "Neon Hook",
          "search \"Neon Hook\" matched \(neonMatches.first?.displayTitle ?? "nothing"), expected Neon Hook")
    return failures
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

        let scanner = MusicArchiveScanner()
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

        // Fixture mode asserts hand-written facts; real-root mode stays exploratory and assertion-free.
        if options.realRoot == nil {
            let failures = verifyFixtureExpectations(result: result, neonMatches: neonMatches)
            if !failures.isEmpty {
                for failure in failures {
                    fputs("fixture assertion failed: \(failure)\n", stderr)
                }
                exit(1)
            }
            print("fixture assertions passed")
        }
    }
}
