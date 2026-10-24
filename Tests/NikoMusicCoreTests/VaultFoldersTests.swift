import Foundation
import NikoMusicCore
import XCTest

/// The folder layout is an on-disk format: these paths are what earlier
/// versions wrote, so a change here breaks existing Vaults.
final class VaultFoldersTests: XCTestCase {
    private let archiveRoot = URL(fileURLWithPath: "/Vault", isDirectory: true)
    private let activeRoot = URL(fileURLWithPath: "/Active", isDirectory: true)
    private let projectID = ProjectID(rawValue: UUID(uuidString: "0A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9")!)
    private let operationID = UUID(uuidString: "FEDCBA98-7654-4321-8FED-CBA987654321")!

    func testArchiveRootFolders() {
        XCTAssertEqual(VaultFolders.generations(in: archiveRoot).path, "/Vault/generations")
        XCTAssertEqual(
            VaultFolders.generation(in: archiveRoot, projectID: projectID, transferID: operationID).path,
            "/Vault/generations/0a1b2c3d-4e5f-4061-8273-94a5b6c7d8e9/generation-fedcba98-7654-4321-8fed-cba987654321"
        )
        XCTAssertEqual(
            VaultFolders.generationFolderName(transferID: operationID),
            "generation-fedcba98-7654-4321-8fed-cba987654321"
        )
        XCTAssertEqual(VaultFolders.staging(in: archiveRoot).path, "/Vault/.niko-staging")
        XCTAssertEqual(
            VaultFolders.staging(in: archiveRoot, projectID: projectID, operationID: operationID).path,
            "/Vault/.niko-staging/0a1b2c3d-4e5f-4061-8273-94a5b6c7d8e9/fedcba98-7654-4321-8fed-cba987654321"
        )
    }

    func testActiveRootFolders() {
        XCTAssertEqual(
            VaultFolders.staging(in: activeRoot, projectID: projectID, operationID: operationID).path,
            "/Active/.niko-staging/0a1b2c3d-4e5f-4061-8273-94a5b6c7d8e9/fedcba98-7654-4321-8fed-cba987654321"
        )
        XCTAssertEqual(
            VaultFolders.recovery(in: activeRoot, transferID: operationID).path,
            "/Active/.niko-recovery/fedcba98-7654-4321-8fed-cba987654321"
        )
    }

    func testEachPreservedCopyGetsItsOwnAttemptFolder() {
        let first = VaultFolders.preservedActiveCopy(in: activeRoot, transferID: operationID, folderName: "Song")
        let second = VaultFolders.preservedActiveCopy(in: activeRoot, transferID: operationID, folderName: "Song")

        XCTAssertNotEqual(first, second)
        for copy in [first, second] {
            XCTAssertEqual(copy.lastPathComponent, "Song")
            XCTAssertEqual(
                copy.deletingLastPathComponent().deletingLastPathComponent().path,
                "/Active/.niko-recovery/fedcba98-7654-4321-8fed-cba987654321"
            )
            let attempt = copy.deletingLastPathComponent().lastPathComponent
            XCTAssertEqual(attempt, attempt.lowercased())
            XCTAssertNotNil(UUID(uuidString: attempt))
        }
    }

    func testReservedNamesInTheArchiveRoot() {
        for name in ["generations", "Generations", ".niko-staging", ".NIKO-STAGING"] {
            XCTAssertTrue(VaultFolders.isReservedInArchiveRoot(name), name)
        }
        for name in ["Song", "generation", ".niko-recovery", "generations-old"] {
            XCTAssertFalse(VaultFolders.isReservedInArchiveRoot(name), name)
        }
    }

    func testReservedNamesInTheActiveRoot() {
        for name in [".niko-staging", ".niko-recovery", ".niko-anything"] {
            XCTAssertTrue(VaultFolders.isReservedInActiveRoot(name), name)
        }
        for name in ["Song", "niko-staging", ".nikostaging", "generations"] {
            XCTAssertFalse(VaultFolders.isReservedInActiveRoot(name), name)
        }
    }

    func testReservedActiveFoldersAreFoundBelowTheRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultFoldersTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for reserved in [".niko-staging/p/r", ".niko-recovery/t/a/Song", "Songs/.niko-old/Song"] {
            XCTAssertTrue(VaultFolders.isInReservedActiveFolder(root.appendingPathComponent(reserved), activeRoot: root), reserved)
        }
        for ordinary in ["Song", "Songs/Song", "niko-staging/Song"] {
            XCTAssertFalse(VaultFolders.isInReservedActiveFolder(root.appendingPathComponent(ordinary), activeRoot: root), ordinary)
        }
        XCTAssertFalse(
            VaultFolders.isInReservedActiveFolder(URL(fileURLWithPath: "/elsewhere/.niko-staging/x"), activeRoot: root),
            "outside the root is the caller's containment check"
        )
    }
}
