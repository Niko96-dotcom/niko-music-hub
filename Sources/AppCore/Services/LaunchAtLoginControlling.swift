import Foundation

public enum LaunchAtLoginError: Error, Equatable, Sendable {
    case registrationFailed(String)
}

public protocol LaunchAtLoginControlling: Sendable {
    @MainActor
    func isEnabled() -> Bool

    @MainActor
    func setEnabled(_ enabled: Bool) throws
}

public struct NoopLaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    @MainActor
    public func isEnabled() -> Bool { false }

    @MainActor
    public func setEnabled(_ enabled: Bool) throws {}
}

public enum VaultLaunchAtLoginDecision: Equatable, Sendable {
    case unchanged
}

/// General's Open at login switch is the only SMAppService writer. Vault
/// automation reads that bit and warns when copies cannot run at login.
public enum VaultLaunchAtLoginPolicy {
    public static let automationWithoutLoginWarning =
        "Automatic archiving is on, but Niko Music Hub will not open at login. Turn on Open at login in General to run copies while you are away."

    public static func decision(for _: VaultSettings) -> VaultLaunchAtLoginDecision {
        .unchanged
    }

    public static func loginItemLabel(isEnabled: Bool) -> String {
        isEnabled ? "Login item: On" : "Login item: Off"
    }

    public static func warning(for settings: VaultSettings, loginItemEnabled: Bool) -> String? {
        guard settings.isEnabled, settings.automaticArchiving, !loginItemEnabled else { return nil }
        return automationWithoutLoginWarning
    }
}

@MainActor
public struct VaultLaunchAtLoginReconciler {
    private let controller: any LaunchAtLoginControlling

    public init(controller: any LaunchAtLoginControlling) {
        self.controller = controller
    }

    /// Reads the login item. Never registers or unregisters SMAppService.
    public func reconcile(settings: VaultSettings) throws {
        _ = VaultLaunchAtLoginPolicy.warning(
            for: settings,
            loginItemEnabled: controller.isEnabled()
        )
    }
}
