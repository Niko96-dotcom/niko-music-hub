import XCTest
@testable import AppCore

@MainActor
final class VaultLaunchAtLoginTests: XCTestCase {
    func testDecisionPreservesGeneralPreferenceUntilVaultAutomationIsEnabled() {
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings()), .setEnabled(true))
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(isEnabled: false)), .unchanged)
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(automaticArchiving: false)), .unchanged)
        XCTAssertEqual(VaultLaunchAtLoginPolicy.decision(for: settings(launchAtLogin: false)), .setEnabled(false))
    }

    func testReconcileFollowsPolicyAndAvoidsRedundantRegistration() throws {
        let controller = RecordingLaunchAtLoginController(enabled: false)
        let reconciler = VaultLaunchAtLoginReconciler(controller: controller)

        try reconciler.reconcile(settings: settings())
        XCTAssertTrue(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true])

        try reconciler.reconcile(settings: settings())
        XCTAssertEqual(controller.requestedStates, [true])

        try reconciler.reconcile(settings: settings(isEnabled: false))
        XCTAssertTrue(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true])

        try reconciler.reconcile(settings: settings(launchAtLogin: false))
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true, false])

        try reconciler.reconcile(settings: settings(automaticArchiving: false))
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.requestedStates, [true, false])
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
