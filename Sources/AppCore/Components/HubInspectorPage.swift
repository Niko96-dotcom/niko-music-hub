import SwiftUI

/// Tool-page scaffold: content on the left, a fixed inspector on the right.
///
/// Left column (flexible): `HubPageHeader` on the shared keyline, an optional
/// live strip (progress / banner) that only exists while something is
/// happening, the page's one bounded object at a fixed height (drop zone,
/// tap pad, capture readout, URL entry), then a flat list that fills the rest.
/// Right column (fixed `inspectorWidth`, sidebar chrome material, hairline seam): the
/// page's options as labelled groups, and the primary action pinned at the
/// bottom so it sits in the same place on every tool.
public struct HubInspectorPage<Header: View, Live: View, Primary: View, List: View, Inspector: View, Action: View>: View {
    public static var inspectorWidth: CGFloat { HubDesignSystem.Size.chromeRailWidth }
    public static var primaryHeight: CGFloat { 168 }
    /// Matches the tools sidebar (`ToolSidebarView`): 12pt inset, 16pt between groups.
    public static var inspectorInset: CGFloat { 12 }
    public static var groupSpacing: CGFloat { 16 }

    @Environment(\.hubTitleRowInset) private var titleRowInset

    private let header: Header
    private let live: Live
    private let primary: Primary
    private let list: List
    private let inspector: Inspector
    private let action: Action

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder live: () -> Live,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder list: () -> List,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder action: () -> Action
    ) {
        self.header = header()
        self.live = live()
        self.primary = primary()
        self.list = list()
        self.inspector = inspector()
        self.action = action()
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                header
                live
                primary
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.primaryHeight)
                // The list is the only part that grows, so it is the only part that
                // scrolls: header, live strip and the bounded object stay on their
                // keylines no matter how many rows exist (a queue or a stem run can
                // be dozens of rows, which otherwise pushes the whole window open).
                ScrollView {
                    list
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, HubToolLayout.horizontalPadding)
            .padding(.top, HubToolLayout.topPadding)
            .padding(.bottom, HubToolLayout.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Seam runs through the title row to the window top like the shell's.
            HubDesignSystem.Palette.separator
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .padding(.top, -titleRowInset)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    // Same rhythm as the tools sidebar: an empty 56pt band beside the
                    // page title, then caption labels on the "Library" keyline with
                    // 34pt controls on the nav-row keyline, 12pt side inset.
                    VStack(alignment: .leading, spacing: Self.groupSpacing) {
                        inspector
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.inspectorInset)
                    .padding(.top, HubToolLayout.topPadding + HubToolLayout.headerHeight)
                    .padding(.bottom, HubToolLayout.bottomPadding)
                }
                Spacer(minLength: 0)
                // First child of `action` is THE primary; it is pinned to the very
                // bottom, secondaries stack above it, so the primary sits at the same
                // point on every tool regardless of how many secondaries exist.
                HubPrimaryLastStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    action
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.inspectorInset)
                .padding(.bottom, HubToolLayout.bottomPadding)
            }
            .frame(width: Self.inspectorWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            // Same chrome material as the tools sidebar: content sits between two
            // matching rails, and this one reaches up through the title row too.
            .hubChromeMaterial(extendAboveBy: titleRowInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One labelled option group in the inspector: caption label, then the control.
public struct HubInspectorGroup<Content: View>: View {
    private let label: String
    private let content: Content

    public init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    public var body: some View {
        // Label → control gap = HubSectionHeader's bottom padding (4), so a
        // 34pt control lands exactly on the sidebar's nav-row keyline.
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(height: 14)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Flat list section for the content column: a caption header row with an
/// optional count and trailing actions, then hairline-separated rows.
public struct HubListSection<Rows: View, Trailing: View>: View {
    private let title: String
    private let count: Int?
    private let trailing: Trailing
    private let rows: Rows

    public init(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder rows: () -> Rows) {
        self.title = title
        self.count = count
        self.trailing = trailing()
        self.rows = rows()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                Text(title)
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                if let count {
                    Text("\(count)")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                Spacer(minLength: 0)
                trailing
            }
            .frame(height: HubDesignSystem.Size.iconButtonSize)
            Divider()
            rows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension HubListSection where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil, @ViewBuilder rows: () -> Rows) {
        self.init(title, count: count, trailing: { EmptyView() }, rows: rows)
    }
}

/// One flat list row: leading text block, trailing detail, hairline below.
public struct HubListRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                leading
                Spacer(minLength: HubDesignSystem.Spacing.controlGap)
                trailing
            }
            .frame(minHeight: 40)
            Divider()
        }
    }
}

/// Single-line empty state for a flat list: names the missing object, nothing else.
public struct HubListEmpty: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }
}

/// Vertical stack whose FIRST subview is placed at the bottom and the rest
/// above it in order. Used for the inspector's pinned action slot.
public struct HubPrimaryLastStack: Layout {
    private let spacing: CGFloat
    public init(spacing: CGFloat) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let total = heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let order = Array(subviews.indices.dropFirst()) + [subviews.startIndex]
        var y = bounds.minY
        for index in order {
            let sub = subviews[index]
            let h = sub.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            sub.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: h))
            y += h + spacing
        }
    }
}
