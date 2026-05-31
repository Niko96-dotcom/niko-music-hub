import SwiftUI

// MARK: - Shell & panels

/// Ambient depth behind the three-column shell (not a flat window fill).
public struct HubShellBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: ambientColors,
                center: .topLeading,
                startRadius: 40,
                endRadius: 900
            )
            RadialGradient(
                colors: secondaryAmbientColors,
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }

    private var ambientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.14, green: 0.16, blue: 0.22).opacity(0.55),
                Color.clear
            ]
        }
        return [
            Color(red: 0.88, green: 0.92, blue: 0.98).opacity(0.9),
            Color.clear
        ]
    }

    private var secondaryAmbientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.10, green: 0.14, blue: 0.18).opacity(0.45),
                Color.clear
            ]
        }
        return [
            Color(red: 0.94, green: 0.96, blue: 1.0).opacity(0.7),
            Color.clear
        ]
    }
}

/// Frosted column (sidebar, inbox, tool well). Avoid unbounded `glassEffect` on full-height stacks.
public struct HubGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(.thickMaterial)
                    shape.fill(panelTint)
                }
                    .overlay {
                        shape.strokeBorder(HubDesignSystem.glassStroke, lineWidth: 0.5)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [HubDesignSystem.glassInnerHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 14, y: 5)
            }
    }

    private var panelTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.35)
    }
}

/// Bounded elevated card (lists, tap surface, inbox rows).
public struct HubGlassCard: ViewModifier {
  private let cornerRadius: CGFloat
  private let selected: Bool

  public init(cornerRadius: CGFloat = HubDesignSystem.Radius.card, selected: Bool = false) {
    self.cornerRadius = cornerRadius
    self.selected = selected
  }

  public func body(content: Content) -> some View {
    content
      .background {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
          .fill(.thinMaterial)
          .overlay {
            shape.strokeBorder(
              selected ? HubDesignSystem.selectedRowStroke : HubDesignSystem.glassStroke,
              lineWidth: selected ? 1.25 : 0.5
            )
          }
          .shadow(color: .black.opacity(selected ? 0.10 : 0.05), radius: selected ? 6 : 3, y: 1)
      }
  }
}

/// Sidebar / nav row selection — soft glass pill, not a solid accent slab.
public struct HubSidebarNavRow: ViewModifier {
  let isSelected: Bool

  public init(isSelected: Bool) {
    self.isSelected = isSelected
  }

  public func body(content: Content) -> some View {
    content
      .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
            .fill(HubDesignSystem.selectedRowFill)
            .overlay {
              RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .strokeBorder(HubDesignSystem.selectedRowStroke, lineWidth: 1)
            }
        }
      }
  }
}

// MARK: - Legacy aliases

/// Solid panel fill — prefer `hubGlassPanel()` for shell columns.
public struct HubPanelBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.modifier(HubGlassPanel())
    }
}

/// Liquid Glass on a bounded accent chip (macOS 26+).
public struct HubAccentGlass: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.modifier(HubGlassCard(cornerRadius: cornerRadius))
    }
}

public extension View {
    func hubShellBackground() -> some View {
        background(HubShellBackground())
    }

    func hubGlassPanel(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) -> some View {
        modifier(HubGlassPanel(cornerRadius: cornerRadius))
    }

    func hubGlassCard(cornerRadius: CGFloat = HubDesignSystem.Radius.card, selected: Bool = false) -> some View {
        modifier(HubGlassCard(cornerRadius: cornerRadius, selected: selected))
    }

    func hubSidebarNavRow(isSelected: Bool) -> some View {
        modifier(HubSidebarNavRow(isSelected: isSelected))
    }

    func hubPanelBackground() -> some View {
        hubGlassPanel()
    }

    func hubAccentGlass(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) -> some View {
        modifier(HubAccentGlass(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, message: "Use hubGlassPanel() or hubGlassCard().")
    func hubGlassChrome() -> some View {
        hubGlassPanel()
    }
}
