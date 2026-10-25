import XCTest

/// Keep Local pins are read and written only through `KeepLocalPins`. Ten hand-built key sets once
/// each matched pins their own way (L106, L048). The compiler keeps the stored keys in
/// `KeepLocalPins.swift`: the set and the initializer that builds one from keys are `private`, and
/// `VaultSettings` stores the `KeepLocalPins` value, so code anywhere else cannot read or build a key
/// set. This test keeps them private.
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
}
