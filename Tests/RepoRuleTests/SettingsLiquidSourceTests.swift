import XCTest

final class SettingsLiquidSourceTests: XCTestCase {
    func testSettingsUsesSharedLiquidSurfacesForPreferenceGroups() throws {
        let source = try settingsSource()

        [
            "hubCard",
            // Grouped form: rows live directly in the section card, so a row no longer
            // nests its own field surface (no cards inside cards).
            "SettingsRow(",
            "SettingsRowDivider",
            "HubSectionHeader",
            "settingsLoadErrorBanner",
            "saveErrorBanner",
            "inlineWarning",
            "archiveRootRow",
            "helperPathRow",
            "HubChoiceChips(",
            "\"Appearance\"",
            "AppAppearance.allCases",
            "appearanceController.apply",
            "HelperExecutableValidation.validate",
            "helperPathError",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Settings Liquid source: \(required)")
        }

        [
            "cardFill",
            "Color.primary.opacity(0.02)",
            "Color.primary.opacity(0.03)",
            "RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card",
            "SettingsSectionImportance",
            "sectionIntent",
        ].forEach { forbidden in
            XCTAssertFalse(source.contains(forbidden), "Settings still defines local card formula: \(forbidden)")
        }
    }

    func testSettingsRowsHaveOneSharedDefinition() throws {
        let settings = try settingsSource()
        let vault = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift",
            encoding: .utf8
        )
        let rows = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsRow.swift",
            encoding: .utf8
        )

        XCTAssertFalse(settings.contains("struct SettingsRow<"))
        XCTAssertFalse(vault.contains("struct SettingsRow<"))
        XCTAssertTrue(rows.contains("struct SettingsRow<Control: View>: View"))
        XCTAssertTrue(rows.contains("struct SettingsRowDivider: View"))
    }

    func testSettingsKeepsSafetyAndAccessibilityHooks() throws {
        let source = try settingsSource()

        [
            "SystemPrivacySettings.openSystemAudioRecordingSettings()",
            "accessibilityLabel: \"Remove from scan list\"",
            "Settings were not saved",
            "context.fileActions.chooseOutputFolder()",
            "context.fileActions.chooseExecutable",
            "ArchiveScanList().adding(",
            "ArchiveScanList().removing(",
            "Read-only. Nothing moves or gets deleted unless you confirm a Project Vault archive",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Settings safety/accessibility source: \(required)")
        }
    }

    /// Settings and Set Up save the scan list and the Vault settings; the archive
    /// follows the store. A file here that reaches into the archive view model
    /// brings back the follow-up call that a new writer forgets.
    func testSettingsAndSetUpNeverReachIntoTheArchiveViewModel() throws {
        let settingsFolder = SourceTestSupport.packageRoot.appendingPathComponent("Sources/NikoMusicHub/Settings")
        let files = try FileManager.default.contentsOfDirectory(atPath: settingsFolder.path)
            .filter { $0.hasSuffix(".swift") }
            .map { "Sources/NikoMusicHub/Settings/\($0)" }
        XCTAssertGreaterThan(files.count, 5)
        for file in files + ["Sources/NikoMusicHub/Onboarding/HubSetupView.swift"] {
            let source = SourceLex.stripped(try SourceTestSupport.read(file))
            XCTAssertFalse(source.contains("ArchiveBrowserViewModel"), file)
            XCTAssertFalse(source.contains("import FeatureArchiveBrowser"), file)
        }
    }

    /// A save can fail from any row of a scrolled pane (the output picker refuses a
    /// folder inside a music root). Inside the scrolling form, after the last card,
    /// the refusal sat below the window and nobody saw it. It is pinned below the form.
    func testSaveErrorIsPinnedOutsideTheScrollingForm() throws {
        let source = SourceLex.stripped(try settingsSource())
        let page = try XCTUnwrap(Self.closureBody(after: "HubToolPage {", in: source), "SettingsView.body has no HubToolPage")
        let inset = try XCTUnwrap(
            Self.closureBody(after: ".safeAreaInset(edge: .bottom, spacing: 0) {", in: source),
            "SettingsView.body has no bottom safe-area inset"
        )

        XCTAssertFalse(SourceLex.containsWord(page, "saveErrorBanner"), "the save error must not scroll with the form")
        XCTAssertTrue(SourceLex.containsWord(inset, "saveErrorBanner"), "the save error is pinned in the bottom inset")
        XCTAssertTrue(SourceLex.containsWord(page, "settingsLoadErrorBanner"), "the load error stays at the top of the form")
    }

    /// The text between the braces of the first `opener` (which ends with `{`).
    private static func closureBody(after opener: String, in source: String) -> String? {
        guard let open = source.range(of: opener) else { return nil }
        var depth = 1
        var index = open.upperBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[open.upperBound..<index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Choosing a vault root reloads the stored settings first. When that load
    /// fails, the folder is not at fault: the view must show the plain repair
    /// sentence and keep "That folder cannot be used" for VaultRootManager only.
    func testChooseRootDoesNotBlameFolderForUnreadableSettings() throws {
        let vault = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift",
            encoding: .utf8
        )
        guard let start = vault.range(of: "private func chooseRoot(") else {
            XCTFail("chooseRoot not found")
            return
        }
        let rest = vault[start.upperBound...]
        guard let end = rest.range(of: "\n    private func ") else {
            XCTFail("chooseRoot body end not found")
            return
        }
        let body = rest[..<end.lowerBound]

        XCTAssertTrue(body.contains("SettingsRepairModel.pausedMessage"), "unreadable settings must show the repair sentence")
        XCTAssertTrue(body.contains("That folder cannot be used"), "VaultRootManager errors keep the folder message")

        guard let load = body.range(of: "settingsStore.loadSettings()"),
              let replace = body.range(of: "replacingRoot(") else {
            XCTFail("chooseRoot must load settings and call replacingRoot")
            return
        }
        XCTAssertTrue(
            body[load.upperBound..<replace.lowerBound].contains("catch"),
            "loadSettings() must be caught separately from replacingRoot so a decoding error is not reported as a bad folder"
        )
    }

    /// The Vault pane offers no background archiving and no login item, and
    /// General's Open at login promises none: the only automatic archiving is
    /// the Done copy, and General's switch is the one SMAppService writer.
    func testVaultSettingsOfferNoBackgroundArchivingAndNoLoginItem() throws {
        let vault = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift",
            encoding: .utf8
        )
        [
            "Archive automatically",
            "untouched",
            "GiB is free",
            "Login item",
            "Open Login Setting",
            "launchAtLogin",
        ].forEach { forbidden in
            XCTAssertFalse(vault.contains(forbidden), "Vault settings still show: \(forbidden)")
        }
        let general = try settingsSource()
        XCTAssertTrue(general.contains("Toggle(\"Open at login\""))
        XCTAssertTrue(general.contains("try context.launchAtLogin.setEnabled(enabled)"))
        XCTAssertFalse(general.contains("archive while you"), "Open at login promises no background archiving")
    }

    private func settingsSource() throws -> String {
        try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )
    }
}
