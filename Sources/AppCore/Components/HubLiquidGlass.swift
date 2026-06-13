import SwiftUI

public typealias HubLiquidSurfaceIntent = HubDesignSystem.Liquid.Intent

/// Full-shell Liquid Studio Glass backdrop for the app frame.
public struct HubLiquidBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let accessibility = liquidAccessibility

        ZStack {
            HubDesignSystem.Liquid.SurfaceFill
                .opaqueTint(for: .backdrop, colorScheme: colorScheme)

            if !accessibility.reduceTransparency {
                LinearGradient(
                    colors: [
                        HubDesignSystem.Liquid.Prismatic.cyan.opacity(colorScheme == .dark ? 0.13 : 0.08),
                        HubDesignSystem.Liquid.Prismatic.violet.opacity(colorScheme == .dark ? 0.10 : 0.06),
                        .clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(colorScheme == .dark ? .screen : .plusLighter)

                RadialGradient(
                    colors: HubDesignSystem.Liquid.Prismatic.backdropGlow + [.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 540
                )
                .blendMode(colorScheme == .dark ? .screen : .plusLighter)
            }
        }
        .overlay {
            if accessibility.highContrast {
                Color.primary.opacity(0.06)
            }
        }
        .ignoresSafeArea()
    }

    private var liquidAccessibility: HubDesignSystem.Liquid.AccessibilityFallback {
        HubDesignSystem.Liquid.AccessibilityFallback(
            reduceTransparency: reduceTransparency,
            highContrast: colorSchemeContrast == .increased
        )
    }
}

/// Shared Liquid Studio Glass panel surface.
public struct HubLiquidPanel: ViewModifier {
    private let cornerRadius: CGFloat
    private let intent: HubLiquidSurfaceIntent
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Liquid.SurfaceLevel.panel.cornerRadius,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.intent = intent
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content.modifier(
            HubLiquidSurface(
                level: .panel,
                intent: intent,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}

/// Shared Liquid Studio Glass card surface.
public struct HubLiquidCard: ViewModifier {
    private let cornerRadius: CGFloat
    private let intent: HubLiquidSurfaceIntent
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Liquid.SurfaceLevel.card.cornerRadius,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.intent = intent
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content.modifier(
            HubLiquidSurface(
                level: .card,
                intent: intent,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}

/// Stable field chrome for search, URL, mode, and metadata inputs.
public struct HubGlassField: ViewModifier {
    private let intent: HubLiquidSurfaceIntent
    private let minHeight: CGFloat

    public init(
        intent: HubLiquidSurfaceIntent = .normal,
        minHeight: CGFloat = HubDesignSystem.Size.buttonMinHeight
    ) {
        self.intent = intent
        self.minHeight = minHeight
    }

    public func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight)
            .modifier(
                HubLiquidSurface(
                    level: .field,
                    intent: intent,
                    cornerRadius: HubDesignSystem.Liquid.SurfaceLevel.field.cornerRadius,
                    interactive: true
                )
            )
    }
}

private struct HubLiquidSurface: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    let level: HubDesignSystem.Liquid.SurfaceLevel
    let intent: HubLiquidSurfaceIntent
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accessibility = liquidAccessibility

        if #available(macOS 26.0, *), !accessibility.reduceTransparency {
            content
                .opacity(intent == .disabled ? 0.62 : 1)
                .glassEffect(
                    .regular
                        .tint(
                            HubDesignSystem.Liquid.SurfaceFill.tint(
                                for: level,
                                intent: intent,
                                colorScheme: colorScheme,
                                accessibility: accessibility
                            )
                        )
                        .interactive(interactive && !reduceMotion),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        HubDesignSystem.Liquid.Stroke.color(for: intent, accessibility: accessibility),
                        lineWidth: HubDesignSystem.Liquid.Stroke.width(for: intent, accessibility: accessibility)
                    )
                }
                .liquidDepth(level: level, intent: intent, colorScheme: colorScheme)
        } else {
            content
                .opacity(intent == .disabled ? 0.62 : 1)
                .background {
                    ZStack {
                        if accessibility.reduceTransparency {
                            shape.fill(
                                HubDesignSystem.Liquid.SurfaceFill.opaqueTint(
                                    for: level,
                                    intent: intent,
                                    colorScheme: colorScheme
                                )
                            )
                        } else {
                            shape.fill(fallbackMaterial)
                            shape.fill(
                                HubDesignSystem.Liquid.SurfaceFill.tint(
                                    for: level,
                                    intent: intent,
                                    colorScheme: colorScheme,
                                    accessibility: accessibility
                                )
                            )
                        }
                    }
                    .overlay {
                        shape.strokeBorder(
                            HubDesignSystem.Liquid.Stroke.color(for: intent, accessibility: accessibility),
                            lineWidth: HubDesignSystem.Liquid.Stroke.width(for: intent, accessibility: accessibility)
                        )
                    }
                    .overlay(alignment: .top) {
                        if !accessibility.reduceTransparency {
                            shape
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            HubDesignSystem.glassInnerHighlight,
                                            HubDesignSystem.Liquid.Prismatic.cyan.opacity(0.025),
                                            .clear,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .center
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .liquidDepth(level: level, intent: intent, colorScheme: colorScheme)
                }
        }
    }

    private var liquidAccessibility: HubDesignSystem.Liquid.AccessibilityFallback {
        HubDesignSystem.Liquid.AccessibilityFallback(
            reduceTransparency: reduceTransparency,
            highContrast: colorSchemeContrast == .increased
        )
    }

    private var fallbackMaterial: Material {
        switch level {
        case .backdrop:
            return .regularMaterial
        case .panel:
            return .thickMaterial
        case .card, .field, .chip:
            return .thinMaterial
        }
    }
}

private extension View {
    func liquidDepth(
        level: HubDesignSystem.Liquid.SurfaceLevel,
        intent: HubLiquidSurfaceIntent,
        colorScheme: ColorScheme
    ) -> some View {
        shadow(
            color: .black.opacity(HubDesignSystem.Liquid.Depth.shadowOpacity(for: level, colorScheme: colorScheme)),
            radius: HubDesignSystem.Liquid.Depth.shadowRadius(for: level, intent: intent),
            y: level == .panel ? 3 : 1
        )
    }
}

public extension View {
    func hubLiquidPanel(
        cornerRadius: CGFloat = HubDesignSystem.Liquid.SurfaceLevel.panel.cornerRadius,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubLiquidPanel(cornerRadius: cornerRadius, intent: intent, interactive: interactive))
    }

    func hubLiquidCard(
        cornerRadius: CGFloat = HubDesignSystem.Liquid.SurfaceLevel.card.cornerRadius,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubLiquidCard(cornerRadius: cornerRadius, intent: intent, interactive: interactive))
    }

    func hubGlassField(
        intent: HubLiquidSurfaceIntent = .normal,
        minHeight: CGFloat = HubDesignSystem.Size.buttonMinHeight
    ) -> some View {
        modifier(HubGlassField(intent: intent, minHeight: minHeight))
    }
}
