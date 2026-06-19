import SwiftUI
import AppKit

/// macOS 14.2-compatible dynamic light/dark Color helper.
///
/// This implements the locked "Color(light:dark:)" intent — see RESEARCH Pitfall 1:
/// `Color(light:dark:)` does NOT exist in any macOS SDK. Use `NSColor(name:dynamicProvider:)` instead.
/// The macOS appearance system re-resolves the color on light/dark mode change with no app code.
@usableFromInline
struct HubDynamicColor {
    @usableFromInline let light: Color
    @usableFromInline let dark: Color
    @usableFromInline init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }
}

/// Returns an `NSColor` that flips between `light` and `dark` based on the current
/// appearance. Explicitly resolves via `.sRGB` color space (Pitfall 8) so the
/// appearance flip does not shift hues.
@usableFromInline
func hubDynamicColor(light: Color, dark: Color) -> NSColor {
    NSColor(name: nil) { appearance in
        // The three dark appearances available on macOS 14.2 (deployment target).
        // `.accessibilityVibrantHighContrastDarkAqua` is NOT in the macOS 14.2 SDK
        // (added later); the high-contrast dark path is covered by `.accessibilityHighContrastDarkAqua`.
        if appearance.bestMatch(from: [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
        ]) != nil {
            NSColor(dark).usingColorSpace(.sRGB) ?? NSColor.black
        } else {
            NSColor(light).usingColorSpace(.sRGB) ?? NSColor.white
        }
    }
}

extension Color {
    /// Convenience initializer that wraps a `HubDynamicColor` (the macOS 14.2-compatible
    /// equivalent of the locked "Color(light:dark:)" pattern).
    init(_ hub: HubDynamicColor) {
        self = Color(nsColor: hubDynamicColor(light: hub.light, dark: hub.dark))
    }
}

/// Shared visual tokens for Niko Music Hub — calm, human, Apple-native chrome.
///
/// Phase 51 ships the semantic token surface (Palette / Typography / Spacing / Radius /
/// Motion / ControlState). Dark-mode RGB values are locked by `calm-native.css`; light-mode
/// values are coherent low-chroma variants. The legacy `Liquid` namespace is kept intact
/// this plan (deleted in Plan 02 after the adapters are rewritten) so `HubLiquidGlass.swift`
/// and `HubMediaSurfaces.swift` compile unchanged.
public enum HubDesignSystem {
    // MARK: - Corner Radii

    public enum Radius {
        public static let shell: CGFloat = 10
        public static let panel: CGFloat = 8
        public static let card: CGFloat = 8
        public static let row: CGFloat = 6
        public static let chip: CGFloat = 5
        public static let pill: CGFloat = .infinity
        public static let button: CGFloat = 6
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let shell: CGFloat = 16
        public static let panel: CGFloat = 14
        public static let section: CGFloat = 12
        public static let cardGap: CGFloat = 10
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
        public static let sidebarWidth: ClosedRange<CGFloat> = 190 ... 250
        public static let inboxWidth: ClosedRange<CGFloat> = 220 ... 300
    }

    // MARK: - Semantic Palette
    //
    // 14+ purpose-named color roles (DS-02/DS-03). Dark-mode RGB values are locked by
    // calm-native.css; light-mode values are coherent low-chroma variants (CONTEXT.md
    // "the agent's Discretion"). Every token flips automatically on appearance change
    // via `NSColor(name:dynamicProvider:)` — no mutable global ThemeManager (DS-09).

    public enum Palette {
        /// Window background, opaque. calm-native --canvas rgb(30,30,31).
        public static let canvas = Color(HubDynamicColor(
            light: Color(.sRGB, red: 236/255, green: 236/255, blue: 238/255, opacity: 1),
            dark:  Color(.sRGB, red: 30/255,  green: 30/255,  blue: 31/255,  opacity: 1)))
        /// NavigationSplitView sidebar. calm-native --sidebar rgb(38,38,40).
        public static let sidebar = Color(HubDynamicColor(
            light: Color(.sRGB, red: 240/255, green: 240/255, blue: 242/255, opacity: 1),
            dark:  Color(.sRGB, red: 38/255,  green: 38/255,  blue: 40/255,  opacity: 1)))
        /// Grouped content surface. calm-native --surface rgb(44,44,46).
        public static let surface = Color(HubDynamicColor(
            light: Color(.sRGB, red: 252/255, green: 252/255, blue: 254/255, opacity: 1),
            dark:  Color(.sRGB, red: 44/255,  green: 44/255,  blue: 46/255,  opacity: 1)))
        /// Popover / raised group. calm-native --surfaceRaised rgb(52,52,55).
        public static let surfaceRaised = Color(HubDynamicColor(
            light: Color(.sRGB, red: 248/255, green: 248/255, blue: 250/255, opacity: 1),
            dark:  Color(.sRGB, red: 52/255,  green: 52/255,  blue: 55/255,  opacity: 1)))
        /// Divider/stroke between surfaces. calm-native --separator rgb(55,55,58).
        public static let separator = Color(HubDynamicColor(
            light: Color(.sRGB, red: 210/255, green: 210/255, blue: 214/255, opacity: 1),
            dark:  Color(.sRGB, red: 55/255,  green: 55/255,  blue: 58/255,  opacity: 1)))
        /// Primary readable text. calm-native --textPrimary rgb(235,235,238).
        public static let textPrimary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 28/255,  green: 28/255,  blue: 30/255,  opacity: 1),
            dark:  Color(.sRGB, red: 235/255, green: 235/255, blue: 238/255, opacity: 1)))
        /// Secondary readable text. calm-native --textSecondary rgb(165,165,172).
        public static let textSecondary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 90/255,  green: 90/255,  blue: 98/255,  opacity: 1),
            dark:  Color(.sRGB, red: 165/255, green: 165/255, blue: 172/255, opacity: 1)))
        /// Tertiary/muted text. calm-native --textTertiary rgb(120,120,128).
        public static let textTertiary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 140/255, green: 140/255, blue: 148/255, opacity: 1),
            dark:  Color(.sRGB, red: 120/255, green: 120/255, blue: 128/255, opacity: 1)))
        /// Subtle neutral selection fill (low-chroma, NOT accent). calm-native --selection rgb(62,62,66).
        public static let selection = Color(HubDynamicColor(
            light: Color(.sRGB, red: 210/255, green: 210/255, blue: 216/255, opacity: 1),
            dark:  Color(.sRGB, red: 62/255,  green: 62/255,  blue: 66/255,  opacity: 1)))
        /// Selection stroke. calm-native --selectionStroke rgb(72,72,78).
        public static let selectionStroke = Color(HubDynamicColor(
            light: Color(.sRGB, red: 190/255, green: 190/255, blue: 196/255, opacity: 1),
            dark:  Color(.sRGB, red: 72/255,  green: 72/255,  blue: 78/255,  opacity: 1)))
        /// Generic focus ring (low-chroma, NOT accent per DS-13). calm-native --focus rgb(78,78,84).
        public static let focus = Color(HubDynamicColor(
            light: Color(.sRGB, red: 180/255, green: 180/255, blue: 186/255, opacity: 1),
            dark:  Color(.sRGB, red: 78/255,  green: 78/255,  blue: 84/255,  opacity: 1)))
        /// Warm muted amber. Reserved for primary action / focus / active playback / meaningful
        /// selection (DS-12/13). Never a panel background. calm-native --accent rgb(198,168,128).
        public static let accent = Color(HubDynamicColor(
            light: Color(.sRGB, red: 168/255, green: 138/255, blue: 98/255,  opacity: 1),
            dark:  Color(.sRGB, red: 198/255, green: 168/255, blue: 128/255, opacity: 1)))
        /// Deeper amber for borders/strokes on accent surfaces. calm-native --accentDeep rgb(168,138,98).
        public static let accentDeep = Color(HubDynamicColor(
            light: Color(.sRGB, red: 140/255, green: 110/255, blue: 72/255,  opacity: 1),
            dark:  Color(.sRGB, red: 168/255, green: 138/255, blue: 98/255,  opacity: 1)))
        /// 16%-opacity accent fill for selected chip backgrounds. calm-native --accentFill rgba(198,168,128,0.16).
        public static let accentFill = Color(HubDynamicColor(
            light: Color(.sRGB, red: 168/255, green: 138/255, blue: 98/255,  opacity: 0.16),
            dark:  Color(.sRGB, red: 198/255, green: 168/255, blue: 128/255, opacity: 0.16)))
        /// Status success — semantic only, never the only carrier (DS-14). calm-native --success rgb(120,170,110).
        public static let success = Color(HubDynamicColor(
            light: Color(.sRGB, red: 95/255,  green: 145/255, blue: 85/255,  opacity: 1),
            dark:  Color(.sRGB, red: 120/255, green: 170/255, blue: 110/255, opacity: 1)))
        /// Status warning — semantic only, never the only carrier (DS-14). calm-native --warning rgb(200,160,90).
        public static let warning = Color(HubDynamicColor(
            light: Color(.sRGB, red: 170/255, green: 130/255, blue: 60/255,  opacity: 1),
            dark:  Color(.sRGB, red: 200/255, green: 160/255, blue: 90/255,  opacity: 1)))
        /// Status danger — semantic only, never the only carrier (DS-14). calm-native --danger rgb(190,100,92).
        public static let danger = Color(HubDynamicColor(
            light: Color(.sRGB, red: 165/255, green: 72/255,  blue: 66/255,  opacity: 1),
            dark:  Color(.sRGB, red: 190/255, green: 100/255, blue: 92/255,  opacity: 1)))
    }

    // MARK: - Colors (compatibility facade — delegates to Palette)
    //
    // Kept so all existing consumers auto-update to the semantic values without an API
    // rename. Plan 02 may restyle individual consumers to read Palette directly.

    public enum Colors {
        /// Warm muted amber (DS-12). Delegates to `Palette.accent`.
        public static let accent = Palette.accent
        /// Neutral hover tint (historical name; NOT accent — DS-13 compliant since it's neutral).
        public static let accentTint = Color.primary.opacity(0.06)
        /// Deeper amber. Delegates to `Palette.accentDeep`.
        public static let accentDeep = Palette.accentDeep
        /// Status success. Delegates to `Palette.success`.
        public static let success = Palette.success
        /// Status warning. Delegates to `Palette.warning`.
        public static let warning = Palette.warning
        /// Status danger. Delegates to `Palette.danger`.
        public static let danger = Palette.danger
        /// Separator. Delegates to `Palette.separator`.
        public static let separator = Palette.separator
        /// Card stroke — kept as-is this plan (Plan 02 may update).
        public static let cardStroke = Color.primary.opacity(0.05)
        /// Selected stroke — kept as-is this plan (Plan 02 may update).
        public static let selectedStroke = Color.primary.opacity(0.12)
    }

    // MARK: - Glass (computed compatibility facade — kept as-is this plan)

    public static var glassStroke: Color { Colors.cardStroke }

    public static var glassInnerHighlight: Color { Color.white.opacity(0.05) }

    public static var selectedRowFill: Color { Color.primary.opacity(0.06) }

    public static var selectedRowStroke: Color { Color.primary.opacity(0.10) }

    // MARK: - Typography
    //
    // Direction A uses the default system typeface (SF Pro), not `.rounded`.
    // Sizes per calm-native.css (--fs-* values converted to pt).

    public enum Typography {
        public static func display() -> Font {
            .system(size: 30, weight: .bold)
        }

        public static func screenTitle() -> Font {
            .system(size: 22, weight: .semibold)
        }

        public static func sectionTitle() -> Font {
            .system(size: 15, weight: .semibold)
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

    // MARK: - Motion
    //
    // Locked durations per CONTEXT.md (150/250/400ms). `duration(_:reduceMotion:)`
    // returns 0 when Reduce Motion is on (A11Y-07).

    public enum Motion {
        public static let short: Double = 0.15
        public static let medium: Double = 0.25
        public static let long: Double = 0.40

        public enum DurationTier: Double, Sendable {
            case short = 0.15
            case medium = 0.25
            case long = 0.40
        }

        /// Returns the duration, or 0 when Reduce Motion is on (A11Y-07).
        public static func duration(_ tier: DurationTier, reduceMotion: Bool) -> Double {
            reduceMotion ? 0 : tier.rawValue
        }
    }

    // MARK: - Control State (DS-05)
    //
    // Seven-case interactive state enum. Replaces the v1.6 `Liquid.Intent` shape
    // with a `pressed` case added for explicit press-state tracking. Behavioral
    // tests instantiate each control in each state and assert the consumed token.

    public enum ControlState: CaseIterable, Sendable {
        case normal
        case hover
        case pressed
        case selected
        case disabled
        case warning
        case error
    }

    // MARK: - Liquid Studio Glass (LEGACY — kept intact this plan, deprecated in Plan 02, deleted in Phase 57)
    //
    // The Liquid namespace stays alive so `HubLiquidGlass.swift`, `HubMediaSurfaces.swift`,
    // `AppShellView.swift`, and `ToolSidebarView.swift` continue to compile unchanged.
    // Plan 02 introduces deprecated thin-wrapper adapters; Phase 57 deletes the namespace
    // outright (MIG-08/13/14). DO NOT grow new feature call sites (enforced by the
    // no-new-call-sites source check landed in a later plan).

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
}
