import SwiftUI

/// Shared visual tokens for Niko Music Hub — calm, human, Apple liquid-glass chrome.
public enum HubDesignSystem {
    // MARK: - Corner Radii

    public enum Radius {
        public static let shell: CGFloat = 14
        public static let panel: CGFloat = 12
        public static let card: CGFloat = 10
        public static let row: CGFloat = 8
        public static let chip: CGFloat = 6
        public static let pill: CGFloat = 18
        public static let button: CGFloat = 8
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let shell: CGFloat = 10
        public static let panel: CGFloat = 16
        public static let section: CGFloat = 24
        public static let cardGap: CGFloat = 8
        public static let controlGap: CGFloat = 8
        public static let inlineGap: CGFloat = 6
    }

    // MARK: - Sizes

    public enum Size {
        public static let sidebarIconFrame: CGFloat = 18
        public static let buttonMinHeight: CGFloat = 32
        public static let iconButtonSize: CGFloat = 30
        public static let chipHeight: CGFloat = 26
        public static let statusDot: CGFloat = 7
        public static let sidebarWidth: ClosedRange<CGFloat> = 200 ... 260
        public static let inboxWidth: ClosedRange<CGFloat> = 260 ... 320
    }

    // MARK: - Colors

    public enum Colors {
        /// Warm indigo accent — hub-owned selection and actions.
        public static let accent = Color(red: 0.35, green: 0.42, blue: 0.95)
        public static let accentTint = accent.opacity(0.12)
        public static let accentDeep = Color(red: 0.28, green: 0.34, blue: 0.82)
        public static let success = Color(red: 0.30, green: 0.78, blue: 0.48)
        public static let warning = Color(red: 0.95, green: 0.68, blue: 0.25)
        public static let danger = Color(red: 0.92, green: 0.34, blue: 0.34)
        public static let separator = Color.primary.opacity(0.08)
        public static let cardStroke = Color.primary.opacity(0.07)
        public static let selectedStroke = accent.opacity(0.35)
    }

    // MARK: - Glass

    public static var glassStroke: Color { Colors.cardStroke }

    public static var glassInnerHighlight: Color { Color.white.opacity(0.10) }

    public static var selectedRowFill: Color { Colors.accentTint }

    public static var selectedRowStroke: Color { Colors.selectedStroke }

    // MARK: - Typography

    public enum Typography {
        public static func display() -> Font {
            .system(size: 56, weight: .bold, design: .rounded)
        }

        public static func screenTitle() -> Font {
            .system(size: 18, weight: .semibold, design: .rounded)
        }

        public static func sectionTitle() -> Font {
            .system(size: 14, weight: .semibold, design: .rounded)
        }

        public static func body() -> Font {
            .system(size: 13, weight: .regular)
        }

        public static func bodySmall() -> Font {
            .system(size: 12, weight: .regular)
        }

        public static func caption() -> Font {
            .system(size: 11, weight: .medium)
        }

        public static func micro() -> Font {
            .system(size: 10, weight: .medium)
        }

        public static func mono(size: CGFloat = 13) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
    }
}
