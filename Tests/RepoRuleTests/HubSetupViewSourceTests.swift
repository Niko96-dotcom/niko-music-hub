import XCTest

/// Set Up installs every helper with one click, in the app's own words and controls: no Homebrew, no
/// Terminal, no welcome line. AGENTS.md row "Design contract"; docs/design-contract.md §5 and §6.
final class HubSetupViewSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Set Up is one click",
        why: "Set Up exists so nobody needs Homebrew or Terminal; copy that sends them there undoes it",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md §5 (copy) and §6 (controls)",
        fix: "Keep Install All, the warm indicator tint and the shared button styles; drop the banned words"
    )

    func testHubSetupViewUsesOneClickCopyAndWarmProgress() {
        Self.rule.expect(
            "Sources/NikoMusicHub/Onboarding/HubSetupView.swift",
            contains: ["Install All", "hub_setup_sheet", ".tint(HubDesignSystem.Colors.indicator)"],
            lacks: ["Welcome to", "brew", "Terminal", ".bordered", "Capsule("]
        )
    }

    func testHelperToolsHealthStripPointsToSetupSheet() {
        Self.rule.expect("Sources/NikoMusicHub/AppShell/HelperToolsHealthStrip.swift", lacks: ["Homebrew"])
    }
}
