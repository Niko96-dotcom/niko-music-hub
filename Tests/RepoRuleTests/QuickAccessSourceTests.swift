import XCTest

/// Quick access (menu bar, Dock, shortcuts) routes through `QuickAccessRouter`: it never builds a tool's
/// view, never hands off output files, and stays an `ObservableObject` (ROUT-07, HAND-04).
/// AGENTS.md row "Design contract"; docs/menu-bar-quick-access.md, docs/architecture.md § SwiftUI state
/// ownership (one-shot router requests).
final class QuickAccessSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Quick access only routes",
        why: "A second place that builds tool views or hands off files would bypass the shell's one pane cache and the inbox's safety gates",
        see: "AGENTS.md row \"Design contract\"; docs/menu-bar-quick-access.md",
        fix: "Ask the router for the tool (a one-shot QuickAccessToolRequest) and let the shell show it"
    )

    func testQuickAccessSourcesDoNotCallMakeView() {
        for name in ["QuickAccessCommand", "QuickAccessEntry", "QuickAccessResolver", "QuickAccessRouter"] {
            Self.rule.expect("Sources/AppCore/QuickAccess/\(name).swift", lacks: ["makeView"], because: "ROUT-07")
        }
    }

    func testQuickAccessRouterDoesNotReferenceOutputHandoff() {
        Self.rule.expect("Sources/AppCore/QuickAccess/QuickAccessRouter.swift", lacks: ["OutputHandoff"], because: "HAND-04")
    }

    func testQuickAccessSourcesDoNotUseObservableMacro() {
        Self.rule.expect("Sources/AppCore/QuickAccess/QuickAccessRouter.swift", lacks: ["@Observable"], because: "the project uses ObservableObject")
    }
}
