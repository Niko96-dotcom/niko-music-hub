import XCTest

/// Keep Local pins are read and written only through `KeepLocalPins`. Ten hand-built key sets once
/// each matched pins their own way (L106, L048). The compiler keeps the stored keys in
/// `KeepLocalPins.swift`: the set and the initializer that builds one from keys are `private`, and
/// `VaultSettings` stores the `KeepLocalPins` value, so a direct read or a hand-built key set elsewhere
/// does not compile. Two paths reach the keys by design: the `Codable` conformance (the settings store;
/// tests plant keys through it) and the internal `salvaging(storedValue:)` (settings repair). This test
/// keeps the keys private and those two paths in the settings code; a generic round trip that names
/// neither is left to review.
/// AGENTS.md row "Keep Local pins"; docs/decisions/021-keep-local-pin-format.md.
final class KeepLocalPinsSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Keep Local pins",
        why: "Hand-built key sets of IDs and path spellings matched pins their own way and missed some",
        see: "AGENTS.md row \"Keep Local pins\"; docs/decisions/021-keep-local-pin-format.md",
        fix: "Ask `VaultSettings.keepLocalPins` (contains, pin, unpin); keep the stored keys private to KeepLocalPins"
    )

    func testTheStoredKeysStayPrivate() {
        let owner = "Sources/AppCore/Settings/KeepLocalPins.swift"
        Self.rule.expect(owner, matching: #"\n    private var storedKeys: Set<String>\n"#, "the stored keys as a `private var`")
        Self.rule.expect(owner, matching: #"\n    private init\(storedKeys: Set<String>\)"#, "the initializer from stored keys as `private`")
        Self.rule.expect(
            "Sources/AppCore/Settings/AppSettings.swift",
            matching: #"\n    public var keepLocalPins: KeepLocalPins\n"#,
            "`VaultSettings` storing the `KeepLocalPins` value"
        )
    }

    func testOnlySettingsCodeDecodesOrSalvagesPins() {
        let allowed: Set<String> = [
            "Sources/AppCore/Settings/KeepLocalPins.swift",  // defines both
            "Sources/AppCore/Settings/AppSettings.swift",  // VaultSettings decodes its pins
            "Sources/AppCore/Settings/SettingsRepair.swift",  // repair salvages a damaged pin list
        ]
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 300).filter { !allowed.contains($0) }
        Self.rule.check(SourceTree.matches(#"KeepLocalPins\.self|\bsalvaging\("#, in: files), "reaches the stored keys outside the settings code")
    }
}
