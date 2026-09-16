#if DEBUG
import SwiftUI
import AppKit

// MARK: - DesignSystemPreviewFeature

/// DEBUG-only DevTool feature that registers the design-system preview surface.
///
/// Reachable via `NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1` + `-ui-tool design-system-preview`.
/// Stripped from release builds by the `#if DEBUG` guard (T-51-10 — no token RGB values
/// or preview surface ships in production).
public struct DesignSystemPreviewFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "design-system-preview",
        displayName: "Design System Preview",
        shortLabel: "Design System",
        systemImage: "swatchpalette",
        capabilities: []
    )

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(DesignSystemPreviewView())
    }
}

// MARK: - DesignSystemPreviewView

/// Renders every semantic token family, control style, control state, and accessibility
/// environment value. This is the VISUAL ACCEPTANCE CRITERION for Phase 51 — the human
/// verifies the calm-native character renders coherently, focus rings are visible, and
/// Reduce Motion / Reduce Transparency / Increase Contrast produce coherent alternatives.
///
/// Never shipped — the enclosing `#if DEBUG` guard strips the entire file from release builds.
public struct DesignSystemPreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.section) {
                paletteSection
                typographySection
                spacingSection
                radiiSection
                motionSection
                controlStatesSection
                controlStylesSection
                accessibilitySection
                focusSection
            }
            .hubToolContentColumn()
        }
        .background(HubShellBackground())
    }

    // MARK: - Palette

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Palette — 17 Semantic Color Roles")

            paletteRow(name: "canvas",        color: HubDesignSystem.Palette.canvas)
            paletteRow(name: "sidebar",       color: HubDesignSystem.Palette.sidebar)
            paletteRow(name: "surface",       color: HubDesignSystem.Palette.surface)
            paletteRow(name: "surfaceRaised", color: HubDesignSystem.Palette.surfaceRaised)
            paletteRow(name: "separator",     color: HubDesignSystem.Palette.separator)
            paletteRow(name: "textPrimary",   color: HubDesignSystem.Palette.textPrimary)
            paletteRow(name: "textSecondary", color: HubDesignSystem.Palette.textSecondary)
            paletteRow(name: "textTertiary",  color: HubDesignSystem.Palette.textTertiary)
            paletteRow(name: "selection",     color: HubDesignSystem.Palette.selection)
            paletteRow(name: "selectionStroke", color: HubDesignSystem.Palette.selectionStroke)
            paletteRow(name: "focus",         color: HubDesignSystem.Palette.focus)
            paletteRow(name: "accent",        color: HubDesignSystem.Palette.accent)
            paletteRow(name: "accentDeep",    color: HubDesignSystem.Palette.accentDeep)
            paletteRow(name: "accentFill",    color: HubDesignSystem.Palette.accentFill)
            paletteRow(name: "success",       color: HubDesignSystem.Palette.success)
            paletteRow(name: "warning",       color: HubDesignSystem.Palette.warning)
            paletteRow(name: "danger",        color: HubDesignSystem.Palette.danger)
        }
    }

    private func paletteRow(name: String, color: Color) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                        .strokeBorder(HubDesignSystem.Palette.separator, lineWidth: 0.5)
                }
                .frame(width: 24, height: 24)

            Text(name)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .frame(width: 140, alignment: .leading)

            Text(rgbString(color))
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    // MARK: - Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Typography — 8 Roles at Actual Size")

            Text("Display 30 / Bold")
                .font(HubDesignSystem.Typography.display())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("Screen Title 22 / Semibold")
                .font(HubDesignSystem.Typography.screenTitle())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("Section Title 15 / Semibold")
                .font(HubDesignSystem.Typography.sectionTitle())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("Body 13 / Regular — main content text")
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("Body Small 12 / Regular — secondary detail")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            Text("Caption 11 / Medium — labels, metadata")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            Text("Micro 10 / Medium — status badges")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            Text("Mono 13 / Medium — rgb(198,168,128)")
                .font(HubDesignSystem.Typography.mono())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    // MARK: - Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Spacing — 6 Proportional Roles")

            spacingRow(name: "shell",      value: HubDesignSystem.Spacing.shell)
            spacingRow(name: "panel",      value: HubDesignSystem.Spacing.panel)
            spacingRow(name: "section",    value: HubDesignSystem.Spacing.section)
            spacingRow(name: "cardGap",    value: HubDesignSystem.Spacing.cardGap)
            spacingRow(name: "controlGap", value: HubDesignSystem.Spacing.controlGap)
            spacingRow(name: "inlineGap",  value: HubDesignSystem.Spacing.inlineGap)
        }
    }

    private func spacingRow(name: String, value: CGFloat) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text(name)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .frame(width: 100, alignment: .leading)

            Rectangle()
                .fill(HubDesignSystem.Palette.accent)
                .frame(width: value * 4, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            Text("\(Int(value))pt")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    // MARK: - Radii

    private var radiiSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Radii — 7 Corner-Radius Roles")

            radiiRow(name: "shell",  value: HubDesignSystem.Radius.shell)
            radiiRow(name: "panel",  value: HubDesignSystem.Radius.panel)
            radiiRow(name: "card",   value: HubDesignSystem.Radius.card)
            radiiRow(name: "row",    value: HubDesignSystem.Radius.row)
            radiiRow(name: "chip",   value: HubDesignSystem.Radius.chip)
            radiiRow(name: "button", value: HubDesignSystem.Radius.button)

            // Pill (.infinity) — show as a capsule
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                Text("pill")
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .frame(width: 80, alignment: .leading)

                Capsule(style: .continuous)
                    .fill(HubDesignSystem.Palette.surfaceRaised)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(HubDesignSystem.Palette.separator, lineWidth: 0.5)
                    }
                    .frame(width: 60, height: 24)

                Text(".infinity")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
    }

    private func radiiRow(name: String, value: CGFloat) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text(name)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .frame(width: 80, alignment: .leading)

            RoundedRectangle(cornerRadius: value, style: .continuous)
                .fill(HubDesignSystem.Palette.surfaceRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: value, style: .continuous)
                        .strokeBorder(HubDesignSystem.Palette.separator, lineWidth: 0.5)
                }
                .frame(width: 40, height: 40)

            Text("\(Int(value))pt")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    // MARK: - Motion

    @State private var motionToggle = false

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Motion — 3 Durations + Reduce Motion")

            HStack(spacing: HubDesignSystem.Spacing.section) {
                Text("short: \(String(format: "%.2f", HubDesignSystem.Motion.short))s")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)

                Text("medium: \(String(format: "%.2f", HubDesignSystem.Motion.medium))s")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)

                Text("long: \(String(format: "%.2f", HubDesignSystem.Motion.long))s")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }

            Text("Reduce Motion: \(reduceMotion ? "ON" : "OFF")")
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(reduceMotion ? HubDesignSystem.Palette.warning : HubDesignSystem.Palette.textPrimary)

            HStack(spacing: HubDesignSystem.Spacing.section) {
                Text("Animated rectangle (tap to toggle):")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)

                Rectangle()
                    .fill(HubDesignSystem.Palette.accent)
                    .frame(width: motionToggle ? 120 : 40, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous))
                    .animation(
                        .easeInOut(duration: HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)),
                        value: motionToggle
                    )
                    .onTapGesture {
                        motionToggle.toggle()
                    }
            }
        }
    }

    // MARK: - Control States

    private var controlStatesSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("ControlState — 7 Cases on hubCard()")

            controlStateRow(.normal,   label: "normal — surface fill + separator stroke")
            controlStateRow(.hover,    label: "hover — same as normal (motion highlights)")
            controlStateRow(.pressed,  label: "pressed — darkened fill, flat elevation")
            controlStateRow(.selected, label: "selected — selection fill + selectionStroke")
            controlStateRow(.disabled, label: "disabled — 62% opacity, separator dimmed")
            controlStateRow(.warning,  label: "warning — amber tint fill + amber stroke")
            controlStateRow(.error,    label: "error — danger tint fill + danger stroke")
        }
    }

    private func controlStateRow(_ state: HubDesignSystem.ControlState, label: String) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text(label)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .padding(HubDesignSystem.Spacing.controlGap)
                .hubCard(state: state)
                .frame(minWidth: 320, alignment: .leading)
        }
    }

    // MARK: - Control Styles

    private var controlStylesSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Control Styles — Buttons + Icon Buttons")

            Text("Labeled buttons — ONLY primary uses accent fill (IA-07 / DS-13):")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            HStack(spacing: HubDesignSystem.Spacing.section) {
                HubLabeledButton(
                    icon: "play.fill",
                    label: "Primary Action",
                    style: .primary,
                    action: {}
                )
                HubLabeledButton(
                    icon: "arrow.down",
                    label: "Secondary",
                    style: .secondary,
                    action: {}
                )
                HubLabeledButton(
                    icon: "info.circle",
                    label: "Ghost",
                    style: .ghost,
                    action: {}
                )
            }

            Text("Icon buttons — toolbar and compactChip:")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .padding(.top, HubDesignSystem.Spacing.inlineGap)

            HStack(spacing: HubDesignSystem.Spacing.section) {
                HubIconButton(
                    systemImage: "waveform",
                    accessibilityLabel: "Toolbar button (normal)",
                    appearance: .toolbar,
                    action: {}
                )
                HubIconButton(
                    systemImage: "star.fill",
                    accessibilityLabel: "Toolbar button (selected)",
                    appearance: .toolbar,
                    isSelected: true,
                    action: {}
                )
                HubIconButton(
                    systemImage: "slider.horizontal.3",
                    accessibilityLabel: "Compact chip",
                    appearance: .compactChip,
                    action: {}
                )
                HubIconButton(
                    systemImage: "checkmark",
                    accessibilityLabel: "Compact chip (selected)",
                    appearance: .compactChip,
                    isSelected: true,
                    chipColors: .archive,
                    action: {}
                )
            }
        }
    }

    // MARK: - Accessibility Environment

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Accessibility — Current Environment Values")

            accessibilityRow("Reduce Motion", value: reduceMotion ? "ON" : "OFF",
                             prominent: reduceMotion)
            accessibilityRow("Reduce Transparency", value: reduceTransparency ? "ON" : "OFF",
                             prominent: reduceTransparency)
            accessibilityRow("Color Scheme Contrast", value: colorSchemeContrast == .increased ? "increased" : "standard",
                             prominent: colorSchemeContrast == .increased)
            accessibilityRow("Color Scheme", value: colorScheme == .dark ? "dark" : "light",
                             prominent: false)
        }
    }

    private func accessibilityRow(_ label: String, value: String, prominent: Bool) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text(label + ":")
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(width: 200, alignment: .leading)

            Text(value)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(prominent ? HubDesignSystem.Palette.warning : HubDesignSystem.Palette.textPrimary)
        }
    }

    // MARK: - Focus Probe

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionHeader("Focus — A11Y-05 Visible Ring (Tab to Focus)")
            FocusProbe()
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(title)
                .font(HubDesignSystem.Typography.sectionTitle())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Rectangle()
                .fill(HubDesignSystem.Palette.separator)
                .frame(height: 0.5)
        }
        .padding(.top, HubDesignSystem.Spacing.section)
    }
}

// MARK: - FocusProbe

/// Demonstrates A11Y-05 — a visible focus ring using `Palette.focus` when the control
/// receives keyboard focus via Tab navigation.
private struct FocusProbe: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            Button("Focusable Control — Tab Here") {}
                .focused($isFocused)
                .buttonStyle(.plain)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .padding(HubDesignSystem.Spacing.controlGap)
                .background {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                        .fill(isFocused ? HubDesignSystem.Palette.focus : HubDesignSystem.Palette.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                        .strokeBorder(
                            isFocused ? HubDesignSystem.Palette.focus : HubDesignSystem.Palette.separator,
                            lineWidth: isFocused ? 2 : 0.5
                        )
                }

            Text(isFocused
                 ? "Focus ring visible — Palette.focus (low-chroma, NOT accent — A11Y-05)"
                 : "Not focused — Tab to this control to see the focus ring")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(isFocused ? HubDesignSystem.Palette.focus : HubDesignSystem.Palette.textTertiary)
        }
    }
}

// MARK: - RGB Helper

/// Extracts the sRGB components of a `Color` via `NSColor` and returns a
/// display string like "rgb(30,30,31)" — useful for verifying the dark-mode
/// RGB values match the calm-native.css lockfile.
private func rgbString(_ color: Color) -> String {
    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
        return "rgb(?)"
    }
    let r = Int((srgb.redComponent * 255).rounded())
    let g = Int((srgb.greenComponent * 255).rounded())
    let b = Int((srgb.blueComponent * 255).rounded())
    return "rgb(\(r),\(g),\(b))"
}

// MARK: - Forced Appearance / Accessibility Previews (NMH-078)

#Preview("Design System · Light") {
    DesignSystemPreviewView()
        .preferredColorScheme(.light)
        .frame(width: 720, height: 900)
}

#Preview("Design System · Dark") {
    DesignSystemPreviewView()
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 900)
}

#Preview("Design System · Increased Contrast") {
    DesignSystemPreviewView()
        .preferredColorScheme(.dark)
        // NMH-078 deviation: FIX-SPECS spells `.environment(\.colorSchemeContrast, .increased)`,
        // but `colorSchemeContrast` is a get-only EnvironmentValues key on this SDK
        // (SwiftUICore declares it `{ get }`; only `_colorSchemeContrast` is `{ get set }`),
        // so the public-key form does not compile. The underscored key is the settable
        // backing store and verified at runtime to propagate to `\.colorSchemeContrast`.
        .environment(\._colorSchemeContrast, .increased)
        .frame(width: 720, height: 900)
}

#Preview("Design System · Reduce Transparency") {
    DesignSystemPreviewView()
        .preferredColorScheme(.dark)
        // NMH-078 deviation: same as above — `accessibilityReduceTransparency` is get-only;
        // `_accessibilityReduceTransparency` is the settable backing store, verified at
        // runtime to propagate to `\.accessibilityReduceTransparency`.
        .environment(\._accessibilityReduceTransparency, true)
        .frame(width: 720, height: 900)
}

#endif
