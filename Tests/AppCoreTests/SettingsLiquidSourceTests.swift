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
            "archiveViewModel.addRoot",
            "archiveViewModel.removeRoot",
            "Read-only. Nothing moves or gets deleted unless you confirm a Project Vault archive",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Settings safety/accessibility source: \(required)")
        }
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

    private func settingsSource() throws -> String {
        try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )
    }
}
