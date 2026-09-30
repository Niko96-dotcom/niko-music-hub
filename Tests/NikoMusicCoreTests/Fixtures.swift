import Foundation
import XCTest

enum CubaseFixtures {
    /// `FIXTURE_EPOCH` in script/fixtures/generate_cubase_archive_fixtures.sh: every fixture
    /// mtime is this or a few hundred seconds after it, never "now".
    static let fixtureEpoch: TimeInterval = 1_700_000_000
    private static let latestFixtureOffset: TimeInterval = 750

    static var archiveRoot: URL {
        packageRoot.appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
    }

    static var summaryTruncationRoot: URL {
        packageRoot.appendingPathComponent("Fixtures/CubaseArchiveSummaryTruncation", isDirectory: true)
    }

    private static var packageRoot: URL {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testsDir.deletingLastPathComponent().deletingLastPathComponent()
    }

    static func ensureGenerated() throws {
        let neonHook = archiveRoot.appendingPathComponent("Neon Hook/Neon Hook.cpr")
        let rankingLab = archiveRoot.appendingPathComponent("Preview Ranking Lab/Mixdown/Lab Song v3 mix.wav")
        let truncationSong = summaryTruncationRoot.appendingPathComponent("Summary Warning 08/notes.txt")
        let raveMaster = archiveRoot.appendingPathComponent("90s Rave/Mixdown/Graffiti master.wav")
        if FileManager.default.fileExists(atPath: neonHook.path),
           FileManager.default.fileExists(atPath: rankingLab.path),
           FileManager.default.fileExists(atPath: raveMaster.path),
           FileManager.default.fileExists(atPath: truncationSong.path) {
            // Git checkouts write the tracked fixtures with checkout-time mtimes, which breaks
            // the equal-mtime tiebreak pairs. Restamping is non-destructive.
            if !hasFixtureMtimes() {
                try runGenerator(arguments: ["--restamp"])
            }
            return
        }
        try runGenerator(arguments: [])
    }

    private static func hasFixtureMtimes() -> Bool {
        let range = fixtureEpoch...(fixtureEpoch + latestFixtureOffset)
        for root in [archiveRoot, summaryTruncationRoot] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return false }
            for case let url as URL in enumerator {
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate,
                    range.contains(modified.timeIntervalSince1970) else { return false }
            }
        }
        return true
    }

    private static func runGenerator(arguments: [String]) throws {
        let script = packageRoot
            .appendingPathComponent("script/fixtures/generate_cubase_archive_fixtures.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "fixture generation failed")
    }
}
