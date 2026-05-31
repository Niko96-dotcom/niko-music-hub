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
        public static let shell: CGFloat = 8
        public static let panel: CGFloat = 12
        public static let section: CGFloat = 20
        public static let cardGap: CGFloat = 6
        public static let controlGap: CGFloat = 8
        public static let inlineGap: CGFloat = 4
    }

    // MARK: - Sizes

    public enum Size {
        public static let sidebarIconFrame: CGFloat = 18
        public static let buttonMinHeight: CGFloat = 32
        public static let iconButtonSize: CGFloat = 30
        public static let chipHeight: CGFloat = 26
        public static let statusDot: CGFloat = 7
        public static let sidebarWidth: ClosedRange<CGFloat> = 190 ... 250
        public static let inboxWidth: ClosedRange<CGFloat> = 220 ... 300
    }

    // MARK: - Colors

    public enum Colors {
        public static let accent = Color.accentColor
        public static let accentTint = Color.primary.opacity(0.06)
        public static let accentDeep = Color.primary.opacity(0.14)
        public static let success = Color(red: 0.30, green: 0.72, blue: 0.45)
        public static let warning = Color(red: 0.85, green: 0.62, blue: 0.20)
        public static let danger = Color(red: 0.82, green: 0.30, blue: 0.30)
        public static let separator = Color.primary.opacity(0.06)
        public static let cardStroke = Color.primary.opacity(0.05)
        public static let selectedStroke = Color.primary.opacity(0.12)
    }

    // MARK: - Glass

    public static var glassStroke: Color { Colors.cardStroke }

    public static var glassInnerHighlight: Color { Color.white.opacity(0.05) }

    public static var selectedRowFill: Color { Color.primary.opacity(0.06) }

    public static var selectedRowStroke: Color { Color.primary.opacity(0.10) }

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
