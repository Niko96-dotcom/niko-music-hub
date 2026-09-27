@testable import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class LiveProjectVaultReuseCancelTests: XCTestCase {
    func testCancelledUsableGenerationCheckThrowsInsteadOfAnsweringUnusable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-reuse-cancel-\(UUID().uuidString)", isDirectory: true)
        let generation = root.appendingPathComponent("Archive/generations/generation", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: generation.appendingPathComponent("Artist Song.cpr"))
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try VaultManifestBuilder().build(at: generation)
        var transfer = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("Active/Artist Song", isDirectory: true),
            stagingURL: root.appendingPathComponent("Archive/.niko-staging/transfer", isDirectory: true),
            destinationURL: generation,
            state: .archiveVerified
        )
        transfer.manifestID = manifest.id
        transfer.manifest = manifest
        let provider = LocalFolderArchiveStorage(root: root.appendingPathComponent("Archive", isDirectory: true))

        let usable = try await LiveProjectVaultRuntime.hasUsableArchiveGeneration(
            transfer, provider: provider, manifestBuilder: VaultManifestBuilder()
        )
        XCTAssertTrue(usable, "the verified generation is usable when the check runs to the end")

        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiveProjectVaultRuntime.hasUsableArchiveGeneration(
                transfer, provider: provider, manifestBuilder: VaultManifestBuilder()
            )
        }.result
        XCTAssertThrowsError(try cancelled.get()) {
            XCTAssertTrue($0 is CancellationError, "a stopped check must not read as an unusable generation: \($0)")
        }
    }
}
