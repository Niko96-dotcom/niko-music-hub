import AppCore
import XCTest

/// Each built-in tool ID is defined once, in `BuiltInToolIDs.swift`; every other file uses the
/// constant. Before, "wav-converter" and "archive-browser" were spelled in eleven files each, and
/// nothing checked that they agreed. AGENTS.md row "Tool IDs"; docs/architecture.md § Tool
/// self-description.
final class ToolIDSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Tool IDs",
        why: "IDs spelled in many files drifted apart, and shell code that compares IDs breaks when a tool is added",
        see: "AGENTS.md row \"Tool IDs\"; docs/architecture.md § Tool self-description",
        fix: "Use the ToolFeatureID constant from BuiltInToolIDs.swift; check `metadata.section == .settings` for Settings"
    )

    static let ownerPath = "Sources/AppCore/Features/BuiltInToolIDs.swift"
    static let ids: [ToolFeatureID] = [.archiveBrowser, .bpmTapper, .wavConverter, .audioRecorder, .downloader, .stemSeparation]

    func testBuiltInToolIDsAreSpelledOnlyInTheirCatalog() {
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 100).filter { $0 != Self.ownerPath }
        let literals = Self.ids.map { NSRegularExpression.escapedPattern(for: "\"\($0.rawValue)\"") }.joined(separator: "|")
        Self.rule.check(SourceTree.matches(literals, in: files, .codeAndStrings), "spells a built-in tool ID")
    }

    /// Settings is known by its section (`ToolSection.settings`), not by its ID: the ID is spelled
    /// only where the Settings tool declares it.
    func testSettingsToolIDIsSpelledOnlyInItsFeature() {
        let owner = "Sources/NikoMusicHub/Settings/SettingsFeature.swift"
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 100).filter { $0 != owner }
        Self.rule.check(SourceTree.matches(#""settings""#, in: files, .codeAndStrings), "spells the Settings tool ID")
        Self.rule.expect(owner, contains: ["section: .settings"])
    }

    /// The IDs are stored and typed (`-ui-tool`, the shell's selection, inbox items).
    func testBuiltInToolIDsKeepTheirStoredStrings() {
        XCTAssertEqual(
            Self.ids.map(\.rawValue),
            ["archive-browser", "bpm-tapper", "wav-converter", "audio-recorder", "downloader", "stem-separation"]
        )
    }
}
