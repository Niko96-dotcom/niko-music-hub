import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The file access owner on its own: which folders a song may open from, what a Vault block
/// does to an open, and when the nearby open error goes away.
@MainActor
final class ArchiveFileAccessModelTests: XCTestCase {
    private struct NoDiagnostics: Diagnostics {
        func log(_ level: DiagnosticLevel, _ message: String) {}
    }

    /// The archive state a test controls, and what the owner reported.
    private final class Host {
        var songs: [Song] = []
        var roots: [URL] = [URL(fileURLWithPath: "/tmp/file-access/Archive", isDirectory: true)]
        var outputFolder = URL(fileURLWithPath: "/tmp/file-access/Output", isDirectory: true)
        var blockedSongIDs: Set<String> = []
        var statuses: [String?] = []
    }

    private func makeModel(_ host: Host) -> ArchiveFileAccessModel {
        ArchiveFileAccessModel(
            opener: MusicItemOpener(workspace: nil),
            fileActions: TestToolContext.make().fileActions,
            diagnostics: NoDiagnostics(),
            dryRunOpen: true,
            host: ArchiveFileAccessHost(
                songs: { host.songs },
                roots: { host.roots },
                outputFolder: { host.outputFolder },
                writeProtectedRoots: { host.roots },
                isVaultBlocked: { host.blockedSongIDs.contains($0.id) },
                vaultBlockReason: { host.blockedSongIDs.contains($0.id) ? "Use Restore & Open." : nil },
                scanDiagnostics: { nil },
                exportContexts: { ArchiveDiagnosticsExportContexts(search: nil, skippedSearch: nil, selectedSong: nil) },
                reportStatus: { host.statuses.append($0) }
            )
        )
    }

    private func song(_ path: String) -> Song {
        Song(folderPath: URL(fileURLWithPath: path, isDirectory: true),
             originalFolderName: (path as NSString).lastPathComponent,
             displayTitle: (path as NSString).lastPathComponent)
    }

    func testASongOpensFromTheRootsTheOutputFolderAndItsOwnFolder() {
        let host = Host()
        let model = makeModel(host)
        let outside = song("/tmp/elsewhere/Loose Song")

        let allowed = model.allowedOpenRoots(for: outside).map(\.path)

        XCTAssertEqual(allowed, [host.roots[0].path, host.outputFolder.path, outside.folderPath.standardizedFileURL.path])
    }

    func testAVaultHeldSongAddsNoFolderAndOpensNothing() {
        let host = Host()
        let held = song("/tmp/elsewhere/Held Song")
        host.blockedSongIDs = [held.id]
        let model = makeModel(host)

        XCTAssertFalse(model.allowedOpenRoots(for: held).contains { $0.path == held.folderPath.standardizedFileURL.path })
        XCTAssertNil(model.preferredRevealURL(for: held))
        XCTAssertThrowsError(try model.openLatestCPR(for: held))
        XCTAssertEqual(model.openError, "Use Restore & Open.", "the refusal shows nearby")
        XCTAssertEqual(host.statuses.last ?? nil, "Use Restore & Open.", "and in the footer")
    }

    func testDismissingTheOpenErrorClearsIt() {
        let host = Host()
        let held = song("/tmp/elsewhere/Held Song")
        host.blockedSongIDs = [held.id]
        let model = makeModel(host)
        _ = try? model.openLatestCPR(for: held)

        model.dismissOpenError()

        XCTAssertNil(model.openError)
    }

    func testDiagnosticsExportBeforeAScanWritesNothing() throws {
        let host = Host()
        let model = makeModel(host)

        try model.exportDiagnostics(to: URL(fileURLWithPath: "/tmp/file-access/never.txt"))

        XCTAssertNil(model.lastDiagnosticsExportPath)
        XCTAssertEqual(host.statuses.last ?? nil, "Scan the archive before exporting diagnostics.")
    }
}
