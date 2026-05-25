import Foundation
import NikoMusicCore

private final class SmokeLogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

enum ArchiveSmokeCommands {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_E2E_SMOKE"] == "1" else {
            return false
        }

        let fixtureRoot = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_FIXTURE_ROOT"]
            ?? defaultFixtureRoot()
        let root = URL(fileURLWithPath: fixtureRoot, isDirectory: true)

        do {
            let scanner = CubaseArchiveScanner()
            let result = try scanner.scan(roots: [root])
            let index = MusicSearchIndex(songs: result.songs)
            let matches = index.search("Neon Hook")
            guard let neon = matches.first else {
                fputs("smoke failed: Neon Hook not found\n", stderr)
                exit(1)
            }

            print("[niko-music-hub-smoke] songs=\(result.songs.count)")
            print("[niko-music-hub-smoke] neon_hook=\(neon.displayTitle)")

            let logBox = SmokeLogBox()
            let opener = MusicItemOpener(log: { logBox.append($0) })
            let dryRun = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
            guard let openResult = try opener.openLatestCPR(for: neon, dryRun: dryRun) else {
                fputs("smoke failed: no latest CPR\n", stderr)
                exit(1)
            }

            print("[niko-music-hub-smoke] dry_run=\(openResult.dryRun)")
            print("[niko-music-hub-smoke] cpr_path=\(openResult.path)")
            if dryRun {
                print(logBox.joined())
            }

            guard openResult.path.contains("Neon Hook"), openResult.path.hasSuffix(".cpr") else {
                fputs("smoke failed: unexpected CPR path \(openResult.path)\n", stderr)
                exit(1)
            }

            if dryRun {
                let combined = logBox.joined()
                guard combined.contains("Neon Hook"), combined.contains(".cpr") else {
                    fputs("smoke failed: dry-run log missing expected CPR path\n", stderr)
                    exit(1)
                }
            }

            print("[niko-music-hub-smoke] ok")
            exit(0)
        } catch {
            fputs("smoke failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func defaultFixtureRoot() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
            .path
    }
}
