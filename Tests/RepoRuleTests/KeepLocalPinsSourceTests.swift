import Foundation
import XCTest

/// ADR 021: Keep Local pins are read and written only through `KeepLocalPins`.
/// Ten hand-built key sets once each matched pins their own way (L106, L048).
/// The raw stored set is `internal` to AppCore, so other modules cannot reach
/// it; inside AppCore only the settings type, settings repair and
/// `KeepLocalPins` itself may.
final class KeepLocalPinsSourceTests: XCTestCase {
    static let owners: Set<String> = [
        "Sources/AppCore/Settings/AppSettings.swift",
        "Sources/AppCore/Settings/SettingsRepair.swift",
        "Sources/AppCore/Settings/KeepLocalPins.swift",
    ]

    func testOnlyTheOwnersTouchTheRawKeepLocalSet() throws {
        let root = SourceTestSupport.packageRoot.standardizedFileURL.path
        let sources = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(root.count + 1)) }
        XCTAssertGreaterThan(files.count, 300, "Sources/ walk found too few files")

        var offenders: [String] = []
        for file in files.sorted() where !Self.owners.contains(file) {
            if Self.usesRawSet(try SourceTestSupport.read(file)) { offenders.append(file) }
        }
        XCTAssertEqual(
            offenders,
            [],
            "Ask `VaultSettings.keepLocalPins` (contains, pin, unpin) instead of the stored keys (ADR 021)."
        )
    }

    /// The detector must see a use inside a string interpolation (the
    /// diagnostics line) and ignore a comment.
    func testDetectorCatchesCodeAndInterpolationsButNotComments() {
        XCTAssertTrue(Self.usesRawSet("settings.vault.keepLocalProjectIDs.formUnion(keys)"))
        XCTAssertTrue(Self.usesRawSet(#""keep_local_projects=\(vault.keepLocalProjectIDs.count)","#))
        XCTAssertFalse(Self.usesRawSet("// keepLocalProjectIDs is internal\nlet pins = vault.keepLocalPins"))
    }

    /// Comments are stripped; strings are kept, because a use can sit inside an
    /// interpolation.
    private static func usesRawSet(_ source: String) -> Bool {
        SourceLex.containsWord(SourceLex.strippedCommentsOnly(source), "keepLocalProjectIDs")
    }
}
