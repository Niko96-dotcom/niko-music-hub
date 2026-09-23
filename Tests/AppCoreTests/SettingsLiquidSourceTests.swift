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
            "accessibilityLabel: \"Remove archive root\"",
            "Settings were not saved",
            "context.fileActions.chooseOutputFolder()",
            "context.fileActions.chooseExecutable",
            "archiveViewModel.addRoot",
            "archiveViewModel.removeRoot",
            "Scanned read-only. Only a confirmed Project Vault archive removes a song folder",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Settings safety/accessibility source: \(required)")
        }
    }

    private func settingsSource() throws -> String {
        try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )
    }
}
