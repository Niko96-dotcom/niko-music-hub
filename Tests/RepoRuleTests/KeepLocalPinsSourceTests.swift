import XCTest

/// Keep Local pins are read and written only through `KeepLocalPins`. Ten hand-built key sets once
/// each matched pins their own way (L106, L048). The raw stored set is `internal` to AppCore, so other
/// modules cannot reach it; inside AppCore only the settings type, settings repair and `KeepLocalPins`
/// itself may. AGENTS.md row "Keep Local pins"; docs/decisions/021-keep-local-pin-format.md.
final class KeepLocalPinsSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Keep Local pins",
        why: "Hand-built key sets of IDs and path spellings matched pins their own way and missed some",
        see: "AGENTS.md row \"Keep Local pins\"; docs/decisions/021-keep-local-pin-format.md",
        fix: "Ask `VaultSettings.keepLocalPins` (contains, pin, unpin) instead of the stored keys"
    )

    static let owners: Set<String> = [
        "Sources/AppCore/Settings/AppSettings.swift",
        "Sources/AppCore/Settings/SettingsRepair.swift",
        "Sources/AppCore/Settings/KeepLocalPins.swift",
    ]

    func testOnlyTheOwnersTouchTheRawKeepLocalSet() {
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 300).filter { !Self.owners.contains($0) }
        Self.rule.check(files.flatMap { Self.rawSetUses(in: SourceTree.read($0, .codeAndStrings), path: $0) }, "reads the raw keepLocalProjectIDs")
    }

    /// The detector must see a use inside a string interpolation (the diagnostics line) and ignore a
    /// comment, so it runs on text with comments blanked and strings kept.
    func testDetectorCatchesCodeAndInterpolationsButNotComments() {
        func uses(_ line: String) -> Int { Self.rawSetUses(in: SourceLex.strippedCommentsOnly(line)).count }
        XCTAssertEqual(uses("settings.vault.keepLocalProjectIDs.formUnion(keys)"), 1)
        XCTAssertEqual(uses(#""keep_local_projects=\(vault.keepLocalProjectIDs.count)","#), 1)
        XCTAssertEqual(uses("// keepLocalProjectIDs is internal\nlet pins = vault.keepLocalPins"), 0)
    }

    private static func rawSetUses(in text: String, path: String = "") -> [SourceTree.Match] {
        SourceTree.matches(SourceTree.regex(#"\bkeepLocalProjectIDs\b"#), in: text, path: path)
    }
}
