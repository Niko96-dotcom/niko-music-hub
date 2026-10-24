import Foundation

public enum LaunchAtLoginError: Error, Equatable, Sendable {
    case registrationFailed(String)
}

public protocol LaunchAtLoginControlling: Sendable {
    @MainActor
    func isEnabled() -> Bool

    @MainActor
    func setEnabled(_ enabled: Bool) throws

    /// True when the login item is registered but macOS waits for the person to
    /// allow it in System Settings › General › Login Items.
    @MainActor
    func needsApproval() -> Bool

    @MainActor
    func openApprovalSettings()
}

public extension LaunchAtLoginControlling {
    @MainActor
    func needsApproval() -> Bool { false }

    @MainActor
    func openApprovalSettings() {}
}

public enum LaunchAtLoginCopy {
    public static let needsApproval =
        "macOS needs your approval. Turn on Niko Music Hub in System Settings › General › Login Items."
}

public struct NoopLaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    @MainActor
    public func isEnabled() -> Bool { false }

    @MainActor
    public func setEnabled(_ enabled: Bool) throws {}
}
