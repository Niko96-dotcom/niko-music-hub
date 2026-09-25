import XCTest
@testable import NikoMusicCore

final class ScanExclusionPolicyTests: XCTestCase {
    func testSkipsBackupFolderDuringScan() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubExclude-\(UUID().uuidString)", isDirectory: true)
        let included = root.appendingPathComponent("Included Song", isDirectory: true)
        let backup = root.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: included.appendingPathComponent("Included Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: backup.appendingPathComponent("Hidden Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = CubaseArchiveScanner(exclusionTerms: ["backup"])
        let result = try scanner.scan(roots: [root])

        XCTAssertEqual(result.songs.map(\.displayTitle), ["Included Song"])
        XCTAssertTrue(result.skippedEntries.contains { $0.label == "backup" })
    }

    func testTermsFoldAccentsAndCaseWithPOSIXLocale() {
        XCTAssertEqual(ScanExclusionPolicy.terms(from: "Café, BACKUP ,  "), ["cafe", "backup"])
        XCTAssertEqual(ScanExclusionPolicy.terms(from: " a , ,b ,,  c "), ["a", "b", "c"])
        XCTAssertEqual(ScanExclusionPolicy.terms(from: "I"), ["i"])
    }

    func testShouldSkipFolderMatchesAccentsSymmetrically() {
        let cafeTerms = ScanExclusionPolicy.terms(from: "cafe")
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "Café", terms: cafeTerms))
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "CAFÉ", terms: cafeTerms))
        // Direct caller-supplied terms with accents normalize the same way.
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "Cafe", terms: ["Café"]))
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "BACKUP", terms: ["backup"]))
        XCTAssertFalse(ScanExclusionPolicy.shouldSkipFolder(named: "Included Song", terms: cafeTerms))
    }

    func testShouldSkipFolderIsTurkishIndependent() {
        // en_US_POSIX folds ASCII "I" to "i", never to dotless "ı".
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "Istanbul", terms: ["istanbul"]))
        XCTAssertTrue(ScanExclusionPolicy.shouldSkipFolder(named: "ISTANBUL", terms: ["istanbul"]))
        XCTAssertFalse(ScanExclusionPolicy.shouldSkipFolder(named: "ıstanbul", terms: ["istanbul"]))
    }
}
