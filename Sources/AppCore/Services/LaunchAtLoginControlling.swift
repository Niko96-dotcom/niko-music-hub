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
    case setEnabled(Bool)
}

/// Project Vault leaves the app's existing general login-item preference alone
/// while Vault automation is off. Once automation is enabled, its explicit
/// launch-at-login preference becomes authoritative.
public enum VaultLaunchAtLoginPolicy {
    public static func decision(for settings: VaultSettings) -> VaultLaunchAtLoginDecision {
        guard settings.isEnabled, settings.automaticArchiving else { return .unchanged }
        return .setEnabled(settings.launchAtLogin)
    }
}

@MainActor
public struct VaultLaunchAtLoginReconciler {
    private let controller: any LaunchAtLoginControlling

    public init(controller: any LaunchAtLoginControlling) {
        self.controller = controller
    }

    public func reconcile(settings: VaultSettings) throws {
        guard case let .setEnabled(desired) = VaultLaunchAtLoginPolicy.decision(for: settings) else {
            return
        }
        guard controller.isEnabled() != desired else { return }
        try controller.setEnabled(desired)
    }
}
