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
            "sectionIntent",
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
        ].forEach { forbidden in
            XCTAssertFalse(source.contains(forbidden), "Settings still defines local card formula: \(forbidden)")
        }
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
            "Read-only scan roots",
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
