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
        /// One width for every chrome rail flanking the content: tools sidebar,
        /// tool inspector, Output Inbox. 240 fits nav labels and 2-column
        /// inspector blocks; equal rails keep the content column centred and
        /// the title-bar icons mirrored.
        public static let chromeRailWidth: CGFloat = 240
        public static let navWidth: CGFloat = chromeRailWidth
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
        /// Window background, opaque. Dark = Codex content column measured rgb(45,45,43)
        /// (2026-09-18): neutral warm-gray, NOT inky blue-black; light = rgb(249).
        public static let canvas = Color(HubDynamicColor(
            light: Color(.sRGB, red: 249/255, green: 249/255, blue: 248/255, opacity: 1),
            dark:  Color(.sRGB, red: 45/255,  green: 45/255,  blue: 43/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 255/255, green: 255/255, blue: 255/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 30/255,  green: 30/255,  blue: 29/255,  opacity: 1)))
        /// Chrome rail fallback fill (Reduce Transparency) + pressed fill. Matches the
        /// live `.sidebar` vibrancy tone of the Codex rail: dark rgb(51,52,49), light rgb(224).
        public static let sidebar = Color(HubDynamicColor(
            light: Color(.sRGB, red: 224/255, green: 224/255, blue: 222/255, opacity: 1),
            dark:  Color(.sRGB, red: 51/255,  green: 52/255,  blue: 49/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 214/255, green: 214/255, blue: 212/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 40/255,  green: 40/255,  blue: 38/255,  opacity: 1)))
        /// Grouped content surface: one step over the canvas (dark 55 on 45).
        public static let surface = Color(HubDynamicColor(
            light: Color(.sRGB, red: 246/255, green: 246/255, blue: 245/255, opacity: 1),
            dark:  Color(.sRGB, red: 55/255,  green: 55/255,  blue: 53/255,  opacity: 1)))
        /// Popover / raised group. calm-native --surfaceRaised rgb(37,39,44).
        public static let surfaceRaised = Color(HubDynamicColor(
            light: Color(.sRGB, red: 250/255, green: 250/255, blue: 249/255, opacity: 1),
            dark:  Color(.sRGB, red: 70/255,  green: 70/255,  blue: 68/255,  opacity: 1)))
        /// Divider/stroke between surfaces. calm-native --separator rgb(52,54,60) — crisp hairline on near-black.
        public static let separator = Color(HubDynamicColor(
            light: Color(.sRGB, red: 222/255, green: 222/255, blue: 222/255, opacity: 1),
            dark:  Color(.sRGB, red: 66/255,  green: 66/255,  blue: 64/255,  opacity: 1),
            lightHigh: Color(.sRGB, red: 150/255, green: 150/255, blue: 150/255, opacity: 1),
            darkHigh:  Color(.sRGB, red: 110/255, green: 110/255, blue: 108/255, opacity: 1)))
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
        /// Tertiary/muted text. NMH-131: the standard pairs below replace the
        /// calm-native --textTertiary rgb(108,110,120) / light rgb(132,132,136),
        /// which measured 3.3-3.7:1 on canvas/surface/sidebar (WCAG AA needs
        /// 4.5:1 at 10-13 pt). Measured post-fix pairs (sRGB, per opaque fill):
        /// dark 140,142,152 -> 5.16 surface, 5.44 sidebar, 5.74 canvas, 4.58 raised;
        /// light 105,105,110 -> 5.05 surface, 4.74 sidebar, 5.18 canvas, 5.23 raised.
        /// Hierarchy holds: tertiary stays dimmer than textSecondary in both
        /// appearances, and dimmer than the Increase Contrast pairs.
        public static let textTertiary = Color(HubDynamicColor(
            light: Color(.sRGB, red: 105/255, green: 105/255, blue: 110/255, opacity: 1),
            dark:  Color(.sRGB, red: 140/255, green: 142/255, blue: 152/255, opacity: 1),
            lightHigh: Color(.sRGB, red: 80/255,  green: 80/255,  blue: 86/255,  opacity: 1),
            darkHigh:  Color(.sRGB, red: 176/255, green: 178/255, blue: 186/255, opacity: 1)))
        /// Codex-quiet neutral selection fill (low-chroma, NOT accent): a flat gray
        /// pill, darker than the rail in light mode and a small step lighter in dark,
        /// like the ChatGPT/Codex sidebar. Measured Codex (2026-09-18): light pill
        /// rgb(210) on a rgb(220) rail (-10), dark rgb(66) on rgb(51) (+15). The
        /// rail is a `.sidebar` vibrancy whose tone drifts with the desktop, so the
        /// pill is a translucent neutral that keeps that step over ANY rail tone
        /// instead of an opaque gray that only matched one backdrop (DS-12/DS-13).
        public static let selection = Color(HubDynamicColor(
            light: Color.black.opacity(0.055),
            dark:  Color.white.opacity(0.09)))
        /// Selection stroke. calm-native --selectionStroke rgb(64,66,74).
        public static let selectionStroke = Color(HubDynamicColor(
            light: Color(.sRGB, red: 208/255, green: 208/255, blue: 208/255, opacity: 1),
            dark:  Color(.sRGB, red: 82/255,  green: 82/255,  blue: 80/255,  opacity: 1)))
        /// Generic focus ring (low-chroma, NOT accent per DS-13). calm-native --focus rgb(80,82,90).
        public static let focus = Color(HubDynamicColor(
            light: Color(.sRGB, red: 198/255, green: 198/255, blue: 198/255, opacity: 1),
            dark:  Color(.sRGB, red: 98/255,  green: 98/255,  blue: 96/255,  opacity: 1)))
        /// Monochrome emphasis (the references are neutral — Knowledge Base / Analog / Finder
        /// chrome carry NO brand tint; color comes from content). "Accent" is now a bright cool
        /// neutral: near-white on dark, near-black on light. Used for primary action / active
        /// playback / meaningful selection. Never a panel background. rgb(232,233,238).
        /// Accent is a locked grey; system Accent Color is not applied to Hub buttons by design.
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
        /// Warm indicator tint for test run (ChatGPT-style terracotta #CC7D5E).
        /// Toggles / sliders / progress only — buttons, pills and selection stay on
        /// neutral `accent`. Separate token so DS-12/DS-13 neutral-accent guards keep passing.
        public static let indicator = Color(HubDynamicColor(
            light: Color(.sRGB, red: 204/255, green: 125/255, blue: 94/255,  opacity: 1),
            dark:  Color(.sRGB, red: 219/255, green: 141/255, blue: 108/255, opacity: 1)))
        /// Pressed/hover depth for the warm indicator (test run).
        public static let indicatorDeep = Color(HubDynamicColor(
            light: Color(.sRGB, red: 181/255, green: 106/255, blue: 78/255,  opacity: 1),
            dark:  Color(.sRGB, red: 201/255, green: 122/255, blue: 92/255,  opacity: 1)))
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
        /// Monochrome neutral accent (DS-12). Delegates to `Palette.accent`.
        public static let accent = Palette.accent
        /// Warm indicator tint (test run). Delegates to `Palette.indicator`.
        public static let indicator = Palette.indicator
        /// Pressed/hover depth for the warm indicator (test run).
        public static let indicatorDeep = Palette.indicatorDeep
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

    // MARK: - Selection (legacy "Glass" facade removed 2026-09-18: glassStroke /
    // glassInnerHighlight were uncalled fake-glass vocabulary — hand-painted strokes,
    // not a system material. The chrome material lives only in
    // HubMaterial.HubGlassBackdrop (.sidebar vibrancy + flat veil). Kept tokens below
    // are the neutral selection fills pinned by HubDesignSystemTokenTests.)

    public static var selectedRowFill: Color { Color.primary.opacity(0.06) }

    public static var selectedRowStroke: Color { Color.primary.opacity(0.10) }

    // MARK: - Typography
    //
    // Direction A uses the default system typeface (SF Pro), not `.rounded`.
    // NMH-134: roles map to SwiftUI `Font.TextStyle` (not fixed `.system(size:)`)
    // so Accessibility → Display → Text Size scales Hub type on macOS 14.2+.
    // No in-app text-size slider; no UIKit/UIFontMetrics/`@ScaledMetric`/iOS Dynamic Type.

    public enum Typography {
        public static func display() -> Font {
            .system(.largeTitle).weight(.bold)
        }

        /// Big live readouts (BPM, recording timer): one size on every tool,
        /// tabular so digits do not jitter.
        public static func readout() -> Font {
            .system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
        }

        public static func screenTitle() -> Font {
            .system(.title).weight(.semibold)
        }

        public static func sectionTitle() -> Font {
            .system(.title3).weight(.semibold)
        }

        public static func body() -> Font {
            .body
        }

        public static func bodySmall() -> Font {
            .callout
        }

        public static func caption() -> Font {
            .subheadline.weight(.medium)
        }

        public static func micro() -> Font {
            .caption.weight(.medium) // stays ≥ 10 pt after NMH-036
        }

        public static func mono(size _: CGFloat = 13) -> Font {
            // `size` kept for source compatibility; intentionally ignored so
            // mono scales with Display text size via the `.body` text style.
            // Call sites needing lining figures use `.monospacedDigit()` on Text.
            .body.weight(.medium).monospaced()
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
