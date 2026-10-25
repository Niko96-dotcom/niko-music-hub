import XCTest

/// The Vault's folder names are an on-disk format with one owner, `VaultFolders` (NikoMusicCore). A
/// site that spells a name itself can drift from it: a missed reserved folder shows phantom song cards,
/// a differently formatted generation name loses a verified copy.
/// AGENTS.md row "Vault records"; docs/architecture.md § Vault folders.
final class VaultFoldersSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Vault folder names",
        why: "A folder name spelled outside VaultFolders drifts from the on-disk format: phantom cards or a lost verified copy",
        see: "AGENTS.md row \"Vault records\"; docs/architecture.md § Vault folders",
        fix: "Build the folder with VaultFolders"
    )

    private static let owner = "Sources/NikoMusicCore/Vault/VaultFolders.swift"

    func testOnlyVaultFoldersSpellsTheFolderNames() {
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 300).filter { $0 != Self.owner }
        Self.rule.check(files.flatMap { file in Self.spellings(in: SourceTree.read(file, .codeAndStrings)).map { "\(file) spells `\($0)`" } })
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
