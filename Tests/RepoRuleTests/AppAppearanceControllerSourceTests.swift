import XCTest

/// The Appearance setting applies to the whole app, so AppKit windows, sheets and menus follow it too.
/// AGENTS.md row "Design contract"; docs/design-contract.md §4b.
final class AppAppearanceControllerSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Appearance applies app-wide",
        why: "A SwiftUI-only color scheme leaves AppKit windows, sheets and menus in the system appearance",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md §4b",
        fix: "Set NSApp.appearance from the chosen AppAppearance's nsAppearanceName"
    )

    func testAppAppearanceControllerSetsNSAppAppearance() {
        Self.rule.expect("Sources/NikoMusicHub/AppAppearanceController.swift", contains: ["NSApp.appearance", "nsAppearanceName"])
    }
}
