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

    // MARK: - Liquid Studio Glass

    /// Liquid Studio Glass tokens translated from the local MythOS-style reference.
    ///
    /// These values model material, depth, prismatic light, and readable controls for
    /// Niko Music Hub. They intentionally do not copy MythOS profile-card/butterfly
    /// content, and the earlier NeuralNote/laptop clip is not a visual reference.
    public enum Liquid {
        public enum SurfaceLevel: CaseIterable, Sendable {
            case backdrop
            case panel
            case card
            case field
            case chip

            public var cornerRadius: CGFloat {
                switch self {
                case .backdrop:
                    return Radius.shell
                case .panel:
                    return Radius.panel
                case .card:
                    return Radius.card
                case .field:
                    return Radius.row
                case .chip:
                    return Radius.chip
                }
            }
        }

        public enum Intent: CaseIterable, Sendable {
            case normal
            case hover
            case selected
            case disabled
            case warning
            case error
        }

        public struct AccessibilityFallback: Equatable, Sendable {
            public let reduceTransparency: Bool
            public let highContrast: Bool

            public init(
                reduceTransparency: Bool = false,
                highContrast: Bool = false
            ) {
                self.reduceTransparency = reduceTransparency
                self.highContrast = highContrast
            }

            public static let standard = AccessibilityFallback()
            public static let reduceTransparency = AccessibilityFallback(reduceTransparency: true)
            public static let highContrast = AccessibilityFallback(highContrast: true)
        }

        public enum Prismatic {
            public static let cyan = Color(red: 0.36, green: 0.86, blue: 0.94)
            public static let violet = Color(red: 0.62, green: 0.48, blue: 0.98)
            public static let rose = Color(red: 0.96, green: 0.42, blue: 0.70)
            public static let amber = Color(red: 0.94, green: 0.70, blue: 0.34)

            public static let backdropGlow = [
                cyan.opacity(0.18),
                violet.opacity(0.14),
                rose.opacity(0.10),
            ]
        }

        public enum SurfaceFill {
            public static func tint(
                for level: SurfaceLevel,
                intent: Intent = .normal,
                colorScheme: ColorScheme = .dark,
                accessibility: AccessibilityFallback = .standard
            ) -> Color {
                if accessibility.reduceTransparency {
                    return opaqueTint(for: level, intent: intent, colorScheme: colorScheme)
                }

                switch (level, intent) {
                case (_, .selected):
                    return Colors.accent.opacity(colorScheme == .dark ? 0.16 : 0.12)
                case (_, .hover):
                    return Colors.accentTint
                case (_, .warning):
                    return Colors.warning.opacity(colorScheme == .dark ? 0.16 : 0.12)
                case (_, .error):
                    return Colors.danger.opacity(colorScheme == .dark ? 0.16 : 0.12)
                case (_, .disabled):
                    return Color.primary.opacity(0.025)
                case (.backdrop, .normal):
                    return colorScheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.22)
                case (.panel, .normal):
                    return colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.34)
                case (.card, .normal):
                    return colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.22)
                case (.field, .normal):
                    return colorScheme == .dark ? Color.white.opacity(0.030) : Color.white.opacity(0.18)
                case (.chip, .normal):
                    return Color.primary.opacity(0.06)
                }
            }

            public static func opaqueTint(
                for level: SurfaceLevel,
                intent: Intent = .normal,
                colorScheme: ColorScheme = .dark
            ) -> Color {
                switch (level, intent) {
                case (_, .selected):
                    return Colors.accent.opacity(colorScheme == .dark ? 0.24 : 0.18)
                case (_, .warning):
                    return Colors.warning.opacity(colorScheme == .dark ? 0.24 : 0.18)
                case (_, .error):
                    return Colors.danger.opacity(colorScheme == .dark ? 0.24 : 0.18)
                case (_, .disabled):
                    return Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05)
                case (.backdrop, _):
                    return colorScheme == .dark
                        ? Color(red: 0.055, green: 0.060, blue: 0.070)
                        : Color(nsColor: .windowBackgroundColor)
                case (.panel, _):
                    return colorScheme == .dark
                        ? Color(red: 0.075, green: 0.080, blue: 0.095)
                        : Color.white.opacity(0.92)
                case (.card, _), (.field, _), (.chip, _):
                    return colorScheme == .dark
                        ? Color(red: 0.095, green: 0.100, blue: 0.115)
                        : Color.white.opacity(0.86)
                }
            }
        }

        public enum Stroke {
            public static func color(
                for intent: Intent = .normal,
                accessibility: AccessibilityFallback = .standard
            ) -> Color {
                if accessibility.highContrast {
                    switch intent {
                    case .selected:
                        return Colors.accent.opacity(0.82)
                    case .warning:
                        return Colors.warning.opacity(0.88)
                    case .error:
                        return Colors.danger.opacity(0.88)
                    default:
                        return Color.primary.opacity(0.36)
                    }
                }

                switch intent {
                case .selected:
                    return selectedRowStroke
                case .hover:
                    return Colors.accent.opacity(0.18)
                case .warning:
                    return Colors.warning.opacity(0.42)
                case .error:
                    return Colors.danger.opacity(0.44)
                case .disabled:
                    return Color.primary.opacity(0.04)
                case .normal:
                    return glassStroke
                }
            }

            public static func width(
                for intent: Intent = .normal,
                accessibility: AccessibilityFallback = .standard
            ) -> CGFloat {
                let base: CGFloat = switch intent {
                case .selected:
                    1.25
                case .warning, .error:
                    1
                case .hover:
                    0.75
                case .normal, .disabled:
                    0.5
                }

                return accessibility.highContrast ? base + 0.75 : base
            }
        }

        public enum Depth {
            public static func shadowRadius(
                for level: SurfaceLevel,
                intent: Intent = .normal
            ) -> CGFloat {
                switch (level, intent) {
                case (.backdrop, _):
                    return 0
                case (.panel, _):
                    return 8
                case (.card, .selected):
                    return 4
                case (.card, _):
                    return 2
                case (.field, _), (.chip, _):
                    return 1
                }
            }

            public static func shadowOpacity(
                for level: SurfaceLevel,
                colorScheme: ColorScheme = .dark
            ) -> Double {
                switch level {
                case .backdrop:
                    return 0
                case .panel:
                    return colorScheme == .dark ? 0.15 : 0.04
                case .card:
                    return colorScheme == .dark ? 0.06 : 0.02
                case .field, .chip:
                    return colorScheme == .dark ? 0.04 : 0.015
                }
            }
        }

        public enum Motion {
            public static let quickResponse: Double = 0.15
            public static let standardResponse: Double = 0.22
            public static let disabledResponse: Double = 0

            public static func duration(reduceMotion: Bool) -> Double {
                reduceMotion ? disabledResponse : quickResponse
            }
        }
    }

    // MARK: - Reference Contract

    public enum Reference {
        public static let approvedAssets = [
            "tmp/mythos-reference/contact_sheet.png",
            "output/imagegen/niko-music-hub-liquid-glass-direction.png",
        ]

        public static let translationNote =
            "MythOS is translated for material, depth, prismatic light, and readable controls only."

        public static let excludedReference =
            "The earlier NeuralNote/laptop clip is not a visual reference for this milestone."
    }

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
