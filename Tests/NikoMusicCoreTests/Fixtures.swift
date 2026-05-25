import Foundation
import XCTest

enum CubaseFixtures {
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
        if FileManager.default.fileExists(atPath: neonHook.path),
           FileManager.default.fileExists(atPath: rankingLab.path),
           FileManager.default.fileExists(atPath: truncationSong.path) {
            return
        }
        let script = packageRoot
            .appendingPathComponent("script/fixtures/generate_cubase_archive_fixtures.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "fixture generation failed")
    }

}
