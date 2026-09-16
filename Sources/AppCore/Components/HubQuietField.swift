import SwiftUI

/// Plain-styled text field that reports keyboard focus into `hubSurface(.field, state:)`.
public struct HubQuietTextField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private let axis: Axis?
    private let lineLimit: ClosedRange<Int>?

    public init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        axis: Axis? = nil,
        lineLimit: ClosedRange<Int>? = nil
    ) {
        self.title = title
        self._text = text
        self.axis = axis
        self.lineLimit = lineLimit
    }

    public var body: some View {
        field
            .quietFieldStyle()
    }

    @ViewBuilder
    private var field: some View {
        if let axis {
            TextField(title, text: $text, axis: axis)
                .lineLimit(lineLimit ?? 1...Int.max)
        } else {
            TextField(title, text: $text)
        }
    }
}

public extension View {
    /// Reference-quiet text field chrome: plain style on an inset field
    /// surface. Replaces `.roundedBorder`, whose focus ring paints the
    /// SYSTEM accent (blue) — banned by the reference spec. When focused,
    /// `hubSurface` draws a 2 pt `Palette.focus` ring (NMH-025).
    func quietFieldStyle() -> some View {
        modifier(HubQuietFieldModifier())
    }
}

private struct HubQuietFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .focused($isFocused)
            .hubSurface(
                .field,
                state: isFocused ? .focused : .normal,
                cornerRadius: HubDesignSystem.Radius.row
            )
    }
}
