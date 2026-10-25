@testable import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import ProjectVaultRuntime
import XCTest

/// ADR 021: one owner for Keep Local matching over the unchanged stored keys.
final class KeepLocalPinsTests: XCTestCase {
    private typealias Project = KeepLocalPins.Project

    /// Real folders under the temporary directory (itself a `/private/var`
    /// alias), a symlinked parent, a dotted spelling and a missing folder.
    private struct Folders {
        let base: URL
        let real: URL
        let other: URL
        let throughLink: URL
        let dotted: URL
        let privateSpelled: URL
        let missing: URL
        let missingPrivateSpelled: URL

        var all: [URL] { [real, other, throughLink, dotted, privateSpelled, missing, missingPrivateSpelled] }
    }

    private func makeFolders() throws -> Folders {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-keep-local-\(UUID().uuidString)", isDirectory: true)
        let realParent = base.appendingPathComponent("Real", isDirectory: true)
        let real = realParent.appendingPathComponent("Song A", isDirectory: true)
        let other = realParent.appendingPathComponent("Song C", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realParent)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let missing = base.appendingPathComponent("Missing/Song B", isDirectory: true)
        return Folders(
            base: base,
            real: real,
            other: other,
            throughLink: link.appendingPathComponent("Song A", isDirectory: true),
            dotted: URL(fileURLWithPath: realParent.path + "/./Song A/../Song A", isDirectory: true),
            privateSpelled: URL(fileURLWithPath: Self.privateSpelling(real.path), isDirectory: true),
            missing: missing,
            missingPrivateSpelled: URL(fileURLWithPath: Self.privateSpelling(missing.path), isDirectory: true)
        )
    }

    private static func privateSpelling(_ path: String) -> String {
        path.hasPrefix("/var/") || path.hasPrefix("/tmp/") ? "/private" + path : path
    }

    /// Every spelling one of the ten former checks compared: raw, standardized,
    /// resolved, the authorization canonical path and the browser canonical path.
    private func formerSpellings(of folder: URL) -> Set<String> {
        let standardized = folder.standardizedFileURL
        return [
            folder.path,
            standardized.path,
            standardized.resolvingSymlinksInPath().path,
            ProjectVaultArchiveAuthorization.canonicalPath(for: folder),
            ArchiveVaultObservation.vaultCanonicalPath(folder),
        ]
    }

    // MARK: - Matching

    func testIDsMatchExactly() {
        let projectID = ProjectID()
        let loose = "loose-project:file:///archive/#bmVvbg=="
        let pins = KeepLocalPins(storedForm: [projectID.description, loose])
        XCTAssertTrue(pins.contains(Project(projectIDs: [projectID])))
        XCTAssertTrue(pins.contains(Project(songIDs: [loose])))
        XCTAssertFalse(pins.contains(Project(projectIDs: [ProjectID()], songIDs: ["loose-project:other"])))
        XCTAssertFalse(KeepLocalPins(storedForm: []).contains(Project(projectIDs: [projectID])))
    }

    func testFoldersMatchByCanonicalPathWhateverTheSpelling() throws {
        let folders = try makeFolders()
        for stored in [folders.real, folders.throughLink, folders.dotted, folders.privateSpelled] {
            var pins = KeepLocalPins(storedForm: [])
            pins.pin(Project(folders: [stored]))
            for asked in [folders.real, folders.throughLink, folders.dotted, folders.privateSpelled] {
                XCTAssertTrue(pins.contains(Project(folders: [asked])), "stored \(stored.path), asked \(asked.path)")
            }
            XCTAssertFalse(pins.contains(Project(folders: [folders.other])))
        }
        var missing = KeepLocalPins(storedForm: [folders.missing.path])
        XCTAssertTrue(missing.contains(Project(folders: [folders.missingPrivateSpelled])), "missing folders still match across the /private alias")
        missing.unpin(Project(folders: [folders.missingPrivateSpelled]))
        XCTAssertTrue(missing.storedForm.isEmpty)
    }

    /// Requirement 1: wherever a former check found a stored key among the
    /// project's IDs or folder spellings, `contains` finds the pin too.
    func testNeverMatchesLessThanTheFormerChecks() throws {
        let folders = try makeFolders()
        let ids = [ProjectID().description, ProjectID().description, folders.real.standardizedFileURL.path, "loose-project:x#y"]
        var seed: UInt64 = 0x4B45_4550
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let universe = Array(Set(ids).union(folders.all.flatMap(formerSpellings(of:))))
        var formerMatches = 0
        for _ in 0..<2_000 {
            let stored = Set((0..<next(4)).map { _ in universe[next(universe.count)] })
            let askedIDs = (0..<next(3)).map { _ in ids[next(ids.count)] }
            let askedFolders = (0..<next(3)).map { _ in folders.all[next(folders.all.count)] }
            let formerKeys = Set(askedIDs).union(askedFolders.flatMap(formerSpellings(of:)))
            guard !stored.isDisjoint(with: formerKeys) else { continue }
            formerMatches += 1
            let project = Project(songIDs: askedIDs, folders: askedFolders)
            XCTAssertTrue(
                KeepLocalPins(storedForm: stored).contains(project),
                "stored \(stored), ids \(askedIDs), folders \(askedFolders.map(\.path))"
            )
        }
        XCTAssertGreaterThan(formerMatches, 200, "the generator must exercise matches")
    }

    // MARK: - Writing and removing

    /// Requirement 3: a pin writes every key the former browser (#1) and
    /// restore (#9) writers wrote, so an older build still finds it.
    func testPinWritesEverySpellingTheFormerWritersWrote() throws {
        let folders = try makeFolders()
        let projectID = ProjectID()
        let songID = folders.throughLink.standardizedFileURL.path
        var pins = KeepLocalPins(storedForm: [])
        pins.pin(Project(projectIDs: [projectID], songIDs: [songID], folders: [folders.throughLink]))

        let standardized = folders.throughLink.standardizedFileURL
        let browserWriter: Set<String> = [
            songID, projectID.description,
            folders.throughLink.path, standardized.path, standardized.resolvingSymlinksInPath().path,
            ArchiveVaultObservation.vaultCanonicalPath(folders.throughLink),
        ]
        let restoreWriter: Set<String> = [
            projectID.description,
            folders.throughLink.path, standardized.path, standardized.resolvingSymlinksInPath().path,
        ]
        XCTAssertTrue(pins.storedForm.isSuperset(of: browserWriter))
        XCTAssertTrue(pins.storedForm.isSuperset(of: restoreWriter))
    }

    /// L106: a pin stored under a catalog project ID (no transfer) and the song
    /// ID leaves nothing behind when Keep Local is turned off.
    func testUnpinRemovesACatalogOnlyProjectIDPin() throws {
        let folders = try makeFolders()
        let recordID = ProjectID()
        let songID = folders.real.standardizedFileURL.path
        var pins = KeepLocalPins(storedForm: [recordID.description, songID])
        pins.unpin(Project(projectIDs: [recordID], songIDs: [songID], folders: [folders.real]))
        XCTAssertTrue(pins.storedForm.isEmpty)
    }

    /// L048: a restore pinned the folder under a symlinked-root spelling; the
    /// toggle names the song's own folder and still removes every key.
    func testUnpinRemovesARestorePinUnderAnAliasedSpelling() throws {
        let folders = try makeFolders()
        let projectID = ProjectID()
        var pins = KeepLocalPins(storedForm: [])
        pins.pin(Project(projectIDs: [projectID], folders: [folders.throughLink]))
        pins.pin(Project(folders: [folders.privateSpelled]))

        pins.unpin(Project(projectIDs: [projectID], songIDs: [folders.real.standardizedFileURL.path], folders: [folders.real]))
        XCTAssertTrue(pins.storedForm.isEmpty, "left: \(pins.storedForm)")
        XCTAssertFalse(pins.contains(Project(folders: [folders.throughLink])))
    }

    func testUnpinKeepsAnotherProjectsKeys() throws {
        let folders = try makeFolders()
        let keep = ProjectID()
        let remove = ProjectID()
        var pins = KeepLocalPins(storedForm: [])
        pins.pin(Project(projectIDs: [keep], folders: [folders.other]))
        pins.pin(Project(projectIDs: [remove], folders: [folders.real]))
        let otherProjectKeys = KeepLocalPins(storedForm: []).pinning(Project(projectIDs: [keep], folders: [folders.other])).storedForm

        pins.unpin(Project(projectIDs: [remove], folders: [folders.throughLink]))
        XCTAssertEqual(pins.storedForm, otherProjectKeys)
        XCTAssertTrue(pins.contains(Project(projectIDs: [keep])))
        XCTAssertFalse(pins.contains(Project(folders: [folders.real])))
    }

    // MARK: - Settings and the browser's rule

    /// The stored format stays: a vault an earlier build wrote (`keepLocalProjectIDs`, an array of
    /// strings) decodes and matches, and encodes back under the same key as the same array, so an older
    /// build reads what this one writes.
    func testVaultSettingsKeepTheStoredFormatOlderBuildsRead() throws {
        let folders = try makeFolders()
        let projectID = ProjectID()
        let written = #"{"isEnabled":true,"keepLocalProjectIDs":["\#(projectID.description)","\#(folders.real.path)"]}"#
        var vault = try JSONDecoder().decode(VaultSettings.self, from: Data(written.utf8))
        XCTAssertTrue(vault.keepLocalPins.contains(Project(projectIDs: [projectID])))
        XCTAssertTrue(vault.keepLocalPins.contains(Project(folders: [folders.throughLink])))
        XCTAssertEqual(vault.keepLocalPins.storedKeyCount, 2)

        func storedArray(_ vault: VaultSettings) throws -> Set<String> {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vault)) as? [String: Any])
            XCTAssertNil(object["keepLocalPins"], "the settings key stays keepLocalProjectIDs")
            return Set(try XCTUnwrap(object["keepLocalProjectIDs"] as? [String]))
        }
        XCTAssertEqual(try storedArray(vault), [projectID.description, folders.real.path])
        vault.keepLocalPins.unpin(Project(folders: [folders.dotted]))
        XCTAssertEqual(try storedArray(vault), [projectID.description])
        vault.keepLocalPins.unpin(Project(projectIDs: [projectID]))
        XCTAssertEqual(try storedArray(vault), [])
        XCTAssertEqual(vault.keepLocalPins, KeepLocalPins())
    }

    func testCanonicalFolderPathIsTheArchiveBrowsersRule() throws {
        let folders = try makeFolders()
        for url in folders.all + [URL(fileURLWithPath: "/private/var"), URL(fileURLWithPath: "/private/tmp/x")] {
            XCTAssertEqual(KeepLocalPins.canonicalFolderPath(url), ArchiveVaultObservation.vaultCanonicalPath(url), url.path)
        }
    }
}

private extension KeepLocalPins {
    func pinning(_ project: Project) -> KeepLocalPins {
        var copy = self
        copy.pin(project)
        return copy
    }
}
