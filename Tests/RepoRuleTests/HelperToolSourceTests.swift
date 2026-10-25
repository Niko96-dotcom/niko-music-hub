import XCTest

/// Helpers are injected: the composition builds the probe and the locator, every tool and the shell read
/// them from `ToolContext.helperHealth`, the locator reads no process environment (the two Tools switches
/// are read only by the runtime), and the probe runs helpers without a shell.
/// AGENTS.md row "Injected helpers"; docs/architecture.md § Helper tools.
final class HelperToolSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Injected helpers",
        why: "A second probe or locator disagrees about which helper is installed; a shell runs whatever the path names",
        see: "AGENTS.md row \"Injected helpers\"; docs/architecture.md § Helper tools",
        fix: "Build the probe and locator in AppComposition, read ToolContext.helperHealth, and run helpers with an argument list"
    )

    func testTheLocatorReadsNoProcessEnvironment() {
        Self.rule.expect("Sources/AppCore/HelperTools/HelperToolLocator.swift", .code, lacks: ["ProcessInfo", "NIKO_MUSIC_HUB_"])
    }

    func testOnlyTheCompositionBuildsAProbeOrALocator() {
        let files = SourceTree.swiftFiles(under: "Sources/").filter {
            ($0.hasPrefix("Sources/Feature") || $0.hasPrefix("Sources/NikoMusicHub/")) && $0 != "Sources/NikoMusicHub/AppComposition.swift"
        }
        Self.rule.check(SourceTree.matches(#"HelperToolProbe\(|HelperToolLocator\("#, in: files), "builds a helper probe or locator")
    }

    func testTheProbeRunsHelpersWithoutAShell() {
        Self.rule.expect("Sources/AppCore/HelperTools/HelperToolProbe.swift", .code, lacks: ["/bin/sh", "\"-c\""])
    }
}
