import SwiftUI
import AppKit

/// macOS 14.2-compatible dynamic light/dark Color helper, with Increase Contrast pairs.
///
/// This implements the locked "Color(light:dark:)" intent — see RESEARCH Pitfall 1:
/// `Color(light:dark:)` does NOT exist in any macOS SDK. Use `NSColor(name:dynamicProvider:)` instead.
/// The macOS appearance system re-resolves the color on light/dark and Increase Contrast
/// with no app ThemeManager. High-contrast appearances exist for `bestMatch(from:)` on 14.2+;
/// `NSAppearance(named:)` returns nil for those names, so tests inject the match name.
@usableFromInline
struct HubDynamicColor {
    @usableFromInline let light: Color
    @usableFromInline let dark: Color
    @usableFromInline let lightHigh: Color
    @usableFromInline let darkHigh: Color
    @usableFromInline init(light: Color, dark: Color, lightHigh: Color? = nil, darkHigh: Color? = nil) {
        self.light = light
        self.dark = dark
        self.lightHigh = lightHigh ?? light
        self.darkHigh = darkHigh ?? dark
    }
}

/// Appearances `bestMatch(from:)` may return. High-contrast names are match keys only.
@usableFromInline
func hubAppearanceMatchCandidates() -> [NSAppearance.Name] {
    [
        .aqua,
        .darkAqua,
        .vibrantLight,
        .vibrantDark,
        .accessibilityHighContrastAqua,
        .accessibilityHighContrastDarkAqua,
        .accessibilityHighContrastVibrantLight,
        .accessibilityHighContrastVibrantDark,
    ]
}

/// Returns an `NSColor` that flips between light/dark and Increase Contrast pairs.
/// Explicitly resolves via `.sRGB` color space (Pitfall 8) so the appearance flip does not shift hues.
///
/// Pass `matching:` to resolve a `bestMatch` name directly. AppKit cannot instantiate
/// high-contrast appearances with `NSAppearance(named:)` (those names return nil).
@usableFromInline
func hubDynamicColor(
    light: Color,
    dark: Color,
    lightHigh: Color? = nil,
    darkHigh: Color? = nil,
    matching appearanceName: NSAppearance.Name? = nil
) -> NSColor {
    let resolvedLightHigh = lightHigh ?? light
    let resolvedDarkHigh = darkHigh ?? dark
    if let appearanceName {
        return hubNSColor(
            matching: appearanceName,
            light: light,
            dark: dark,
            lightHigh: resolvedLightHigh,
            darkHigh: resolvedDarkHigh
        )
    }
    return NSColor(name: nil) { appearance in
        hubNSColor(
            matching: appearance.bestMatch(from: hubAppearanceMatchCandidates()),
            light: light,
            dark: dark,
            lightHigh: resolvedLightHigh,
            darkHigh: resolvedDarkHigh
        )
    }
}

/// Picks the light/dark or Increase Contrast pair for an `NSAppearance.Name` from `bestMatch(from:)`.
@usableFromInline
func hubNSColor(
    matching appearanceName: NSAppearance.Name?,
    light: Color,
    dark: Color,
    lightHigh: Color,
    darkHigh: Color
) -> NSColor {
    let picked: Color
    let fallback: NSColor
    switch appearanceName {
    case .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
        picked = darkHigh
        fallback = .black
    case .accessibilityHighContrastAqua, .accessibilityHighContrastVibrantLight:
        picked = lightHigh
        fallback = .white
    case .darkAqua, .vibrantDark:
        picked = dark
        fallback = .black
    default:
        picked = light
        fallback = .white
    }
    return NSColor(picked).usingColorSpace(.sRGB) ?? fallback
}

extension Color {
    /// Convenience initializer that wraps a `HubDynamicColor` (the macOS 14.2-compatible
    /// equivalent of the locked "Color(light:dark:)" pattern).
    init(_ hub: HubDynamicColor) {
        self = Color(nsColor: hubDynamicColor(
            light: hub.light,
            dark: hub.dark,
            lightHigh: hub.lightHigh,
            darkHigh: hub.darkHigh
        ))
    }
}

/// Shared visual tokens for Niko Music Hub — calm, human, Apple-native chrome.
///
/// This is the semantic token surface (Palette / Typography / Spacing / Radius / Motion /
/// ControlState). Dark-mode RGB values are locked by `calm-native.css`; light-mode values are
/// coherent low-chroma variants. The legacy `Liquid` namespace and its `HubLiquidGlass.swift`
/// adapters are deleted — use the semantic tokens directly.
public enum HubDesignSystem {
    // MARK: - Corner Radii

    public enum Radius {
        public static let shell: CGFloat = 10
        public static let panel: CGFloat = 8
        public static let card: CGFloat = 8
        public static let row: CGFloat = 8
        public static let chip: CGFloat = 7
        public static let pill: CGFloat = .infinity
        public static let button: CGFloat = 7
        /// Floating overlays — popovers, sheets, feature callouts.
        public static let popover: CGFloat = 12
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let shell: CGFloat = 16
        public static let panel: CGFloat = 14
        public static let section: CGFloat = 12
        public static let cardGap: CGFloat = 12
        public static let controlGap: CGFloat = 10
        public static let inlineGap: CGFloat = 6
        /// Comfortable interior padding for a bounded card (references breathe — not cramped).
        public static let cardPadding: CGFloat = 16
        /// Gap between stacked list rows/cards.
        public static let rowGap: CGFloat = 10
        /// Interior padding for a scrollable content column.
        public static let columnPadding: CGFloat = 20
        /// Vertical breathing room above a section header (references: ~20px before a new group).
        public static let sectionHeaderTop: CGFloat = 0
        /// Caption line + bottom padding in a section header band (pairs with `sectionHeaderTop`).
        public static let sectionHeaderBandHeight: CGFloat = 12 + 4
        /// Standard nav/sidebar row height (references: 36-44px web ≈ 34pt native).
        public static let navRowHeight: CGFloat = 34
        /// Tall page-title header band (references: ~52-56px).
        public static let headerBandHeight: CGFloat = 52
    }

    // MARK: - Sizes

    public enum Size {
        public static let sidebarIconFrame: CGFloat = 18
        public static let buttonMinHeight: CGFloat = 32
        public static let iconButtonSize: CGFloat = 30
        public static let chipHeight: CGFloat = 28
        public static let statusDot: CGFloat = 10
        public static let sidebarWidth: ClosedRange<CGFloat> = 190 ... 250
        public static let inboxWidth: ClosedRange<CGFloat> = 220 ... 300
        /// Icon-rail width (collapsed nav mode).
        public static let railWidth: CGFloat = 64
        /// Labeled navigation sidebar width (references: ~230-260px web ≈ 224pt native).
        public static let navWidth: CGFloat = 224
    }

    // MARK: - Elevation (DEPTH-01)
    //
    // Semantic drop-shadow specs so depth is a first-class token, not an ad-hoc `.shadow`
    // sprinkled across views. Raised surfaces read as physical layers over the inky canvas.

    public struct Shadow: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat
        public init(color: Color, radius: CGFloat, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.y = y
        }
    }

    public enum Elevation {
        /// Flush with the surface — no lift.
        public static let flat = Shadow(color: .clear, radius: 0, y: 0)
        /// List rows / resting cards — almost flush, like grouped settings rows.
        public static let low = Shadow(
            color: Color(HubDynamicColor(light: Color.black.opacity(0.035), dark: Color.black.opacity(0.14))),
            radius: 1,
            y: 0
        )
        /// Hovered / selected cards — present, but still quiet.
        public static let medium = Shadow(
            color: Color(HubDynamicColor(light: Color.black.opacity(0.06), dark: Color.black.opacity(0.22))),
            radius: 4,
            y: 1
        )
        /// Popovers / floating overlays — reads as detached from the window.
        public static let high = Shadow(
            color: Color(HubDynamicColor(light: Color.black.opacity(0.10), dark: Color.black.opacity(0.34))),
            radius: 14,
            y: 7
        )
    }

    // MARK: - Highlight (DEPTH-02)
    //
    // Light-catching accents (top rim, body sheen, hairlines) as tokens — these are the glassy
    // edges that separate a premium surface from a flat rectangle. Neutral white/black opacities
    // that flip with appearance via HubDynamicColor (NMH-074): dark uses a white highlight,
    // light uses a dark (black) highlight so the rim stays visible on a light fill.

    public enum Highlight {
        /// Bright top rim on a raised surface (the edge that catches light).
        /// Dark: white 0.04; light: black 0.06.
        public static let rim = Color(HubDynamicColor(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.04)))
        /// Stronger rim for selected / emphasized surfaces.
        public static let rimStrong = Color(HubDynamicColor(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.07)))
        /// Soft vertical body sheen (top a touch brighter than the fill in dark, a touch
        /// darker than the fill in light).
        public static let sheen = Color(HubDynamicColor(light: Color.black.opacity(0.03), dark: Color.white.opacity(0.015)))
        /// Darker underside edge, opposite the rim.
        public static let underside = Color.black.opacity(0.05)
        /// Subtle neutral hairline (dividers, quiet strokes). Dark: white 0.045; light: black.
        public static let hairline = Color(HubDynamicColor(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.045)))
    }

    // MARK: - Semantic Palette
    //
    // 14+ purpose-named color roles (DS-02/DS-03). Dark-mode RGB values are locked by
    // calm-native.css; light-mode values are coherent low-chroma variants (CONTEXT.md
    // "the agent's Discretion"). Increase Contrast pairs live on the same provider
    // (lightHigh/darkHigh). Every token flips automatically on appearance change
    // via `NSColor(name:dynamicProvider:)` — no mutable global ThemeManager (DS-09).

    public enum Palette {
        /// Window background, opaque. calm-native --canvas rgb(17,18,21) — inky near-black, faint cool.
        public static let canvas = Color(HubDynamicColor(
            light: Color(.sRGB, red: 249/255, green: 249/255, blue: 248/255, opacity: 1),
            dark:  Color(.sRGB, red: 17/255,  green: 18/255,  blue: 21/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 255/255, green: 255/255, blue: 255/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 12/255,  green: 13/255,  blue: 16/255,  opacity: 1)))
        /// NavigationSplitView sidebar. calm-native --sidebar rgb(23,24,28).
        public static let sidebar = Color(HubDynamicColor(
            light: Color(.sRGB, red: 238/255, green: 239/255, blue: 239/255, opacity: 1),
            dark:  Color(.sRGB, red: 23/255,  green: 24/255,  blue: 28/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 226/255, green: 226/255, blue: 226/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 18/255,  green: 19/255,  blue: 23/255,  opacity: 1)))
        /// Grouped content surface. calm-native --surface rgb(28,29,33).
        public static let surface = Color(HubDynamicColor(
            light: Color(.sRGB, red: 246/255, green: 246/255, blue: 245/255, opacity: 1),
            dark:  Color(.sRGB, red: 28/255,  green: 29/255,  blue: 33/255,  opacity: 1)))
        /// Popover / raised group. calm-native --surfaceRaised rgb(37,39,44).
        public static let surfaceRaised = Color(HubDynamicColor(
            light: Color(.sRGB, red: 250/255, green: 250/255, blue: 249/255, opacity: 1),
            dark:  Color(.sRGB, red: 37/255,  green: 39/255,  blue: 44/255,  opacity: 1)))
        /// Divider/stroke between surfaces. calm-native --separator rgb(52,54,60) — crisp hairline on near-black.
        public static let separator = Color(HubDynamicColor(
            light: Color(.sRGB, red: 222/255, green: 222/255, blue: 222/255, opacity: 1),
            dark:  Color(.sRGB, red: 52/255,  green: 54/255,  blue: 60/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 90/255,  green: 92/255,  blue: 100/255, opacity: 1)))
        /// Primary readable text. calm-native --textPrimary rgb(237,238,241). Dark high-contrast keeps the same RGB.
        public static let textPrimary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 28/255,  green: 28/255,  blue: 30/255,  opacity: 1),
            dark:  Color(.sRGB, red: 237/255, green: 238/255, blue: 241/255, opacity: 1)))
        /// Secondary readable text. calm-native --textSecondary rgb(156,158,167).
        public static let textSecondary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 90/255,  green: 90/255,  blue: 98/255,  opacity: 1),
            dark:  Color(.sRGB, red: 156/255, green: 158/255, blue: 167/255, opacity: 1),
            lightHigh: Color(.sRGB, red: 60/255,  green: 60/255,  blue: 66/255,  opacity: 1),
            darkHigh:  Color(.sRGB, red: 196/255, green: 198/255, blue: 206/255, opacity: 1)))
        /// Tertiary/muted text. calm-native --textTertiary rgb(108,110,120).
        public static let textTertiary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 132/255, green: 132/255, blue: 136/255, opacity: 1),
            dark:  Color(.sRGB, red: 108/255, green: 110/255, blue: 120/255, opacity: 1),
            lightHigh: Color(.sRGB, red: 80/255,  green: 80/255,  blue: 86/255,  opacity: 1),
            darkHigh:  Color(.sRGB, red: 176/255, green: 178/255, blue: 186/255, opacity: 1)))
        /// Subtle neutral selection fill (low-chroma, NOT accent). calm-native --selection rgb(46,48,54).
        public static let selection = Color(HubDynamicColor(
            light: Color(.sRGB, red: 225/255, green: 225/255, blue: 224/255, opacity: 1),
            dark:  Color(.sRGB, red: 46/255,  green: 48/255,  blue: 54/255,  opacity: 1)))
        /// Selection stroke. calm-native --selectionStroke rgb(64,66,74).
        public static let selectionStroke = Color(HubDynamicColor(
            light: Color(.sRGB, red: 208/255, green: 208/255, blue: 208/255, opacity: 1),
            dark:  Color(.sRGB, red: 64/255,  green: 66/255,  blue: 74/255,  opacity: 1)))
        /// Generic focus ring (low-chroma, NOT accent per DS-13). calm-native --focus rgb(80,82,90).
        public static let focus = Color(HubDynamicColor(
            light: Color(.sRGB, red: 198/255, green: 198/255, blue: 198/255, opacity: 1),
            dark:  Color(.sRGB, red: 80/255,  green: 82/255,  blue: 90/255,  opacity: 1)))
        /// Monochrome emphasis (the references are neutral — Knowledge Base / Analog / Finder
        /// chrome carry NO brand tint; color comes from content). "Accent" is now a bright cool
        /// neutral: near-white on dark, near-black on light. Used for primary action / active
        /// playback / meaningful selection. Never a panel background. rgb(232,233,238).
        public static let accent = Color(HubDynamicColor(
            light: Color(.sRGB, red: 48/255,  green: 50/255,  blue: 58/255,  opacity: 1),
            dark:  Color(.sRGB, red: 232/255, green: 233/255, blue: 238/255, opacity: 1)))
        /// Dimmer neutral for borders/strokes on emphasized surfaces. rgb(205,207,214).
        public static let accentDeep = Color(HubDynamicColor(
            light: Color(.sRGB, red: 66/255,  green: 68/255,  blue: 78/255,  opacity: 1),
            dark:  Color(.sRGB, red: 205/255, green: 207/255, blue: 214/255, opacity: 1)))
        /// 12%-opacity neutral fill for selected chip backgrounds. rgba(232,233,238,0.12).
        public static let accentFill = Color(HubDynamicColor(
            light: Color(.sRGB, red: 48/255,  green: 50/255,  blue: 58/255,  opacity: 0.10),
            dark:  Color(.sRGB, red: 232/255, green: 233/255, blue: 238/255, opacity: 0.12)))
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
        /// Cool azure accent (DS-12). Delegates to `Palette.accent`.
        public static let accent = Palette.accent
        /// Neutral hover tint (historical name; NOT accent — DS-13 compliant since it's neutral).
        public static let accentTint = Color.primary.opacity(0.06)
        /// Deeper azure. Delegates to `Palette.accentDeep`.
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
    // Interactive state enum including `.focused` for quiet-field rings (NMH-025).
    // Behavioral tests instantiate each control in each state and assert the consumed token.

    public enum ControlState: CaseIterable, Sendable {
        case normal
        case hover
        case pressed
        case selected
        case disabled
        case warning
        case error
        case focused
    }
}
