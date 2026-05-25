import Foundation
import XCTest

enum CubaseFixtures {
    static var archiveRoot: URL {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
    }

    static func ensureGenerated() throws {
        let neonHook = archiveRoot.appendingPathComponent("Neon Hook/Neon Hook.cpr")
        if FileManager.default.fileExists(atPath: neonHook.path) { return }
        let script = archiveRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("script/fixtures/generate_cubase_archive_fixtures.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
