import XCTest

/// Settings uses the shared grouped form, keeps its safety and accessibility hooks, saves to the store
/// instead of reaching into the archive, and offers no background archiving.
/// AGENTS.md rows "Design contract" and "Automatic archiving"; docs/design-contract.md §4b,
/// docs/architecture.md § Archive scan list, docs/architecture-map.md gap 8.
final class SettingsLiquidSourceTests: XCTestCase {
    static let design = RepoRule(
        name: "Settings surfaces",
        why: "Settings is a grouped form on the shared rows; local card formulas and lost hooks drift from the contract",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md §4b",
        fix: "Build rows with SettingsRow inside the section's hubCard and keep the listed hooks"
    )
    static let archiving = RepoRule(
        name: "Automatic archiving",
        why: "The copy-only Done copy is the only automatic archiving; Settings saves to the store and the archive follows it",
        see: "AGENTS.md row \"Automatic archiving\"; docs/architecture-map.md gap 8; docs/architecture.md § Archive scan list",
        fix: "Save through the settings store or ArchiveScanList; offer no background archiving or Vault login item"
    )

    private static let settings = "Sources/NikoMusicHub/Settings/SettingsView.swift"
    private static let vault = "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift"

    func testSettingsUsesSharedLiquidSurfacesForPreferenceGroups() {
        // Grouped form: rows live directly in the section card, so a row no longer nests its own field
        // surface (no cards inside cards).
        Self.design.expect(
            Self.settings,
            contains: [
                "hubCard", "SettingsRow(", "SettingsRowDivider", "HubSectionHeader", "settingsLoadErrorBanner", "saveErrorBanner",
                "inlineWarning", "archiveRootRow", "helperPathRow", "HubChoiceChips(", "\"Appearance\"", "AppAppearance.allCases",
                "appearanceController.apply", "HelperExecutableValidation.validate", "helperPathError",
            ],
            lacks: [
                "cardFill", "Color.primary.opacity(0.02)", "Color.primary.opacity(0.03)",
                "RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card", "SettingsSectionImportance", "sectionIntent",
            ]
        )
    }

    func testSettingsRowsHaveOneSharedDefinition() {
        Self.design.expect(Self.settings, lacks: ["struct SettingsRow<"])
        Self.design.expect(Self.vault, lacks: ["struct SettingsRow<"])
        Self.design.expect("Sources/NikoMusicHub/Settings/SettingsRow.swift",
                           contains: ["struct SettingsRow<Control: View>: View", "struct SettingsRowDivider: View"])
    }

    func testSettingsKeepsSafetyAndAccessibilityHooks() {
        Self.design.expect(Self.settings, contains: [
            "SystemPrivacySettings.openSystemAudioRecordingSettings()", "accessibilityLabel: \"Remove from scan list\"",
            "Settings were not saved", "context.fileActions.chooseOutputFolder()", "context.fileActions.chooseExecutable",
            "ArchiveScanList().adding(", "ArchiveScanList().removing(",
            "Read-only. Nothing moves or gets deleted unless you confirm a Project Vault archive",
        ])
    }

    /// Settings and Set Up save the scan list and the Vault settings; the archive follows the store. A
    /// file here that reaches into the archive view model brings back the follow-up call that a new
    /// writer forgets.
    func testSettingsAndSetUpNeverReachIntoTheArchiveViewModel() {
        let files = SourceTree.swiftFiles(under: "Sources/NikoMusicHub/Settings/", atLeast: 6) + ["Sources/NikoMusicHub/Onboarding/HubSetupView.swift"]
        for file in files {
            Self.archiving.expect(file, .code, lacks: ["ArchiveBrowserViewModel", "import FeatureArchiveBrowser"])
        }
    }

    /// A save can fail from any row of a scrolled pane (the output picker refuses a folder inside a
    /// music root). Inside the scrolling form, after the last card, the refusal sat below the window and
    /// nobody saw it. It is pinned below the form.
    func testSaveErrorIsPinnedOutsideTheScrollingForm() {
        let source = SourceTree.read(Self.settings, .code)
        guard let page = source.range(of: "HubToolPage {"),
              let inset = source.range(of: ".safeAreaInset(edge: .bottom, spacing: 0) {") else {
            return Self.design.check(["\(Self.settings) has no HubToolPage with a bottom safe-area inset"])
        }
        let form = SourceTree.balanced(source, from: page.upperBound, open: "{", close: "}")
        let pinned = SourceTree.balanced(source, from: inset.upperBound, open: "{", close: "}")
        Self.design.require(!SourceLex.containsWord(form, "saveErrorBanner"), "the save error scrolls with the form in \(Self.settings)")
        Self.design.require(SourceLex.containsWord(pinned, "saveErrorBanner"), "the save error is not pinned in the bottom inset of \(Self.settings)")
        Self.design.require(SourceLex.containsWord(form, "settingsLoadErrorBanner"), "the load error left the top of the form in \(Self.settings)")
    }

    /// Choosing a vault root reloads the stored settings first. When that load fails, the folder is not
    /// at fault: the view shows the plain repair sentence and keeps "That folder cannot be used" for
    /// VaultRootManager only.
    func testChooseRootDoesNotBlameFolderForUnreadableSettings() {
        let vault = SourceTree.read(Self.vault)
        guard let start = vault.range(of: "private func chooseRoot("),
              let end = vault[start.upperBound...].range(of: "\n    private func ") else {
            return Self.design.check(["\(Self.vault) has no chooseRoot body"])
        }
        let body = vault[start.upperBound..<end.lowerBound]
        Self.design.require(body.contains("SettingsRepairModel.pausedMessage"), "chooseRoot no longer shows the repair sentence for unreadable settings")
        Self.design.require(body.contains("That folder cannot be used"), "chooseRoot no longer keeps the folder message for VaultRootManager errors")
        guard let load = body.range(of: "settingsStore.loadSettings()"), let replace = body.range(of: "replacingRoot(") else {
            return Self.design.check(["chooseRoot no longer loads settings and calls replacingRoot"])
        }
        Self.design.require(body[load.upperBound..<replace.lowerBound].contains("catch"),
                            "chooseRoot catches loadSettings() together with replacingRoot, so a decoding error reads as a bad folder")
    }

    /// The Vault pane offers no background archiving and no login item, and General's Open at login
    /// promises none: the only automatic archiving is the Done copy, and General's switch is the one
    /// SMAppService writer.
    func testVaultSettingsOfferNoBackgroundArchivingAndNoLoginItem() {
        Self.archiving.expect(Self.vault, lacks: ["Archive automatically", "untouched", "GiB is free", "Login item", "Open Login Setting", "launchAtLogin"])
        Self.archiving.expect(Self.settings, contains: ["Toggle(\"Open at login\"", "try context.launchAtLogin.setEnabled(enabled)"],
                              lacks: ["archive while you"])
    }
}
