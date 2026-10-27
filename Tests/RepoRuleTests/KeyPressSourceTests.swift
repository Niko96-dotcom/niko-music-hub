import XCTest

/// SwiftUI calls an `onKeyPress` action inside a view update, where an observable object that publishes is
/// undefined behavior. A plain `.handled` after a model change logged the "Publishing changes from within view
/// updates" fault on every Esc and Return in the archive and every key on the BPM tap pad (live check,
/// 2026-10-27). An action decides at once and returns `.ignored` or `.handledAfterViewUpdate { change }`.
/// AGENTS.md row "Key presses"; docs/design-contract.md §4.
final class KeyPressSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Key presses",
        why: "SwiftUI runs a key action inside a view update, and a model change published there is undefined behavior",
        see: "AGENTS.md row \"Key presses\"; docs/design-contract.md §4",
        fix: "Return .handledAfterViewUpdate { change } (AppCore's HubKeyPress.swift) instead of making the change and returning .handled"
    )

    static let helper = "Sources/AppCore/Components/HubKeyPress.swift"

    func testEveryHandledKeyChangesAfterTheViewUpdate() {
        let found = SourceTree.matches(Self.pattern, in: SourceTree.swiftFiles(under: "Sources/", atLeast: 300))
        Self.rule.check(found.filter { $0.path != Self.helper }, "handles a key at once")
        Self.rule.require(found.contains { $0.path == Self.helper }, "\(Self.helper) no longer returns .handled; update this rule")
    }

    /// The detector must catch the shipped mistakes, or it guards nothing.
    func testDetectorCatchesTheShippedMistakes() {
        let regex = SourceTree.regex(Self.pattern)
        let shipped = [
            "viewModel.showBoard()\n                return .handled",
            "guard playPause() else { return .ignored }\n        return .handled",
            "return active ? .handled : .ignored",
        ]
        for line in shipped {
            XCTAssertFalse(SourceTree.matches(regex, in: SourceLex.stripped(line)).isEmpty, "Detector misses: \(line)")
        }
        let allowed = [
            "return .handledAfterViewUpdate { viewModel.showBoard() }",
            "return .handledAfterViewUpdate(playPause)",
            "guard isActiveTool else { return .ignored }",
            "// `.handled` consumes the key",
        ]
        for line in allowed {
            XCTAssertEqual(SourceTree.matches(regex, in: SourceLex.stripped(line)), [], "Detector flags allowed code: \(line)")
        }
    }

    private static let pattern = #"\.handled\b"#
}
