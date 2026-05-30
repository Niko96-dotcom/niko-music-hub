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
