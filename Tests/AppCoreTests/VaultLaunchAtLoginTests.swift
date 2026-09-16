import XCTest
@testable import AppCore

@MainActor
final class VaultLaunchAtLoginTests: XCTestCase {
    func testDecisionNeverWritesTheLoginItem() {
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings()), .unchanged)
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(isEnabled: false)), .unchanged)
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(automaticArchiving: false)), .unchanged)
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(launchAtLogin: false)), .unchanged)
    }

    func testEnablingVaultAutomationDoesNotFlipSMAppServiceUnlessGeneralIsOn() throws {
        let generalOff = RecordingLaunchAtLoginController(enabled: false)
        try VaultLaunchAtLoginReconciler(controller: generalOff).reconcile(settings: settings())
        XCTAssertFalse(generalOff.enabled)
        XCTAssertEqual(generalOff.requestedStates, [])

        let generalOn = RecordingLaunchAtLoginController(enabled: true)
        try VaultLaunchAtLoginReconciler(controller: generalOn).reconcile(
            settings: settings(launchAtLogin: false)
        )
        XCTAssertTrue(generalOn.enabled)
        XCTAssertEqual(generalOn.requestedStates, [])
    }

    func testGeneralToggleIsSingleSourceOfTruth() throws {
        let controller = RecordingLaunchAtLoginController(enabled: false)
        let reconciler = VaultLaunchAtLoginReconciler(controller: controller)

        try reconciler.reconcile(settings: settings())
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [])

        try controller.setEnabled(true)
        XCTAssertTrue(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true])

        try reconciler.reconcile(settings: settings(launchAtLogin: false))
        XCTAssertTrue(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true])

        try controller.setEnabled(false)
        try reconciler.reconcile(settings: settings())
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true, false])
    }

    func testWarningWhenAutomationNeedsLoginItem() {
        XCTAssertEqual(
            VaultLaunchAtLoginPolicy.warning(for: settings(), loginItemEnabled: false),
            VaultLaunchAtLoginPolicy.automationWithoutLoginWarning
        )
        XCTAssertNil(VaultLaunchAtLoginPolicy.warning(for: settings(), loginItemEnabled: true))
        XCTAssertNil(
            VaultLaunchAtLoginPolicy.warning(
                for: settings(automaticArchiving: false),
                loginItemEnabled: false
            )
        )
        XCTAssertNil(
            VaultLaunchAtLoginPolicy.warning(
                for: settings(isEnabled: false),
                loginItemEnabled: false
            )
        )
        XCTAssertEqual(VaultLaunchAtLoginPolicy.loginItemLabel(isEnabled: true), "Login item: On")
        XCTAssertEqual(VaultLaunchAtLoginPolicy.loginItemLabel(isEnabled: false), "Login item: Off")
    }

    func testSettingsSurfacesKeepASingleLoginWriter() throws {
        let general = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/SettingsView.swift")
        XCTAssertTrue(general.contains("Toggle(\"Open at login\""))
        XCTAssertTrue(
            general.contains(
                "Opens Niko Music Hub when you log in to this Mac. Project Vault automatic archiving needs this so copies can run while you are away."
            )
        )

        let vault = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift")
        XCTAssertFalse(vault.contains("Launch at login for automation"))
        XCTAssertFalse(vault.contains("reconcileLaunchAtLogin"))
        XCTAssertFalse(vault.contains("VaultLaunchAtLoginReconciler"))
        XCTAssertFalse(vault.contains("$0.vault.launchAtLogin = true"))
        XCTAssertTrue(vault.contains("Open Login Setting"))
        XCTAssertTrue(vault.contains("VaultLaunchAtLoginPolicy.warning"))
        XCTAssertTrue(general.contains("hubOpenSettingsPane"))
        XCTAssertTrue(general.contains("HubSettingsPane.general"))
    }

    private func settings(
        isEnabled: Bool = true,
        automaticArchiving: Bool = true,
        launchAtLogin: Bool = true
    ) -> VaultSettings {
        VaultSettings(
            isEnabled: isEnabled,
            automaticArchiving: automaticArchiving,
            launchAtLogin: launchAtLogin
        )
    }
}

@MainActor
private final class RecordingLaunchAtLoginController: LaunchAtLoginControlling, @unchecked Sendable {
    var enabled: Bool
    var requestedStates: [Bool] = []

    init(enabled: Bool) { self.enabled = enabled }

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
        requestedStates.append(enabled)
    }
}
