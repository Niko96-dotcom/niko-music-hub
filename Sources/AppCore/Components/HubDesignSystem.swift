import SwiftUI

/// Shared visual tokens for Niko Music Hub — calm, human, Apple liquid-glass chrome.
public enum HubDesignSystem {
    public enum Radius {
        public static let shell: CGFloat = 16
        public static let panel: CGFloat = 14
        public static let card: CGFloat = 12
        public static let row: CGFloat = 10
        public static let chip: CGFloat = 8
        public static let pill: CGFloat = 20
    }

    public enum Spacing {
        public static let shell: CGFloat = 14
        public static let panel: CGFloat = 16
        public static let section: CGFloat = 20
    }

    /// Hairline on frosted panels (adapts in light/dark).
    public static var glassStroke: Color {
        Color.primary.opacity(0.09)
    }

    public static var glassInnerHighlight: Color {
        Color.white.opacity(0.14)
    }

    public static var selectedRowFill: Color {
        Color.accentColor.opacity(0.18)
    }

    public static var selectedRowStroke: Color {
        Color.accentColor.opacity(0.42)
    }

    public enum Typography {
        public static func screenTitle() -> Font {
            .system(size: 22, weight: .semibold, design: .rounded)
        }

        public static func sectionTitle() -> Font {
            .system(size: 16, weight: .semibold, design: .rounded)
        }

        public static func body() -> Font {
            .system(size: 13, weight: .regular)
        }

        public static func caption() -> Font {
            .system(size: 11, weight: .medium)
        }
    }
}
