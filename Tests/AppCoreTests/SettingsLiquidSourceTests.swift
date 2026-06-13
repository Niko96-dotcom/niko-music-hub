import XCTest

final class SettingsLiquidSourceTests: XCTestCase {
    func testSettingsUsesSharedLiquidSurfacesForPreferenceGroups() throws {
        let source = try settingsSource()

        [
            "hubGlassGroup",
            "hubLiquidCard",
            "hubGlassField",
            "sectionIntent",
            "settingsLoadErrorBanner",
            "saveErrorBanner",
            "inlineWarning",
            "archiveRootRow",
            "helperPathRow",
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
