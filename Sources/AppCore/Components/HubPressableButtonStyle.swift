import SwiftUI

/// Custom buttons keep a press state in addition to hover (HIG Buttons; NMH-026).
/// Hover animation stays on callers via `HubDesignSystem.Motion.duration`. Press snaps.
public struct HubPressableButtonStyle: ButtonStyle {
    var reduceMotion: Bool

    public nonisolated static let pressedOpacity: Double = 0.92

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .environment(\.hubButtonPressed, configuration.isPressed)
            .animation(nil, value: configuration.isPressed)
            .transaction { transaction in
                if reduceMotion {
                    transaction.disablesAnimations = true
                }
            }
    }
}

enum HubButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hubButtonPressed: Bool {
        get { self[HubButtonPressedKey.self] }
        set { self[HubButtonPressedKey.self] = newValue }
    }
}
