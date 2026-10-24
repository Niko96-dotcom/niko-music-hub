import XCTest

/// The Vault's folder names are an on-disk format with one owner,
/// `VaultFolders` (NikoMusicCore). A site that spells a name itself can drift
/// from it: a missed reserved folder shows phantom song cards, a differently
/// formatted generation name loses a verified copy.
final class VaultFoldersSourceTests: XCTestCase {
    private static let owner = "Sources/NikoMusicCore/Vault/VaultFolders.swift"

    func testOnlyVaultFoldersSpellsTheFolderNames() throws {
        let root = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
            guard relative != Self.owner else { continue }
            let code = SourceLex.strippedCommentsOnly(try String(contentsOf: url, encoding: .utf8))
            offenders += Self.spellings(in: code).map { "\(relative): \($0)" }
        }
        XCTAssertEqual(offenders, [], "build Vault folders with VaultFolders")
    }

    /// The detector must catch the shapes the code used before `VaultFolders`.
    func testDetectorCatchesTheOldSpellings() {
        let shipped = [
            #"archiveRoot.appendingPathComponent(".niko-staging", isDirectory: true)"#,
            #".appendingPathComponent("generations", isDirectory: true)"#,
            #".appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true)"#,
            #"activeRoot.appendingPathComponent(".niko-recovery", isDirectory: true)"#,
            #"$0.hasPrefix(".niko-")"#,
            #"root.appendingPathComponent("active/.niko-staging/fixture", isDirectory: true)"#,
        ]
        for line in shipped {
            XCTAssertFalse(Self.spellings(in: line).isEmpty, "Detector misses: \(line)")
        }
        let allowed = [
            #"VaultFolders.generation(in: archiveRoot, projectID: projectID, transferID: id)"#,
            #".appendingPathComponent(".niko-music-hub-write-probe", isDirectory: false)"#,
            #"let generations = snapshot.generations"#,
        ]
        for line in allowed {
            XCTAssertEqual(Self.spellings(in: line), [], "Detector flags allowed code: \(line)")
        }
    }

    /// Comments are stripped first, so any hit is inside a string literal.
    private static let fragments = [".niko-staging", ".niko-recovery", #""generations""#, #""generation-"#, #"".niko-""#]

    static func spellings(in code: String) -> [String] {
        fragments.filter { code.contains($0) }
    }
}
