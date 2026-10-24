import SwiftUI

/// A key a tool page answers itself (design contract §4): Return runs the page's
/// primary key, Esc its cancel key. `HubInspectorPage` is the only place that binds
/// them. While a page has no enabled cancel key, Esc does what the shell's
/// Edit ▸ Cancel does (`HubShellEscape`), so a page declares one only when Esc must
/// mean something else than cancelling its tool's job.
public struct HubPageKey {
    public let title: String
    public let isEnabled: Bool
    let perform: @MainActor () -> Void

    public init(_ title: String, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }

    /// The key `HubInspectorPage` binds: only an enabled one, and only on the
    /// visible page. The shell keeps a page you left mounted (`AppShellView`), so
    /// its key buttons would otherwise still take Return and Esc.
    static func installed(_ key: HubPageKey?, onVisiblePage: Bool) -> HubPageKey? {
        guard onVisiblePage, let key, key.isEnabled else { return nil }
        return key
    }
}

/// Tool-page scaffold: content on the left, a fixed inspector on the right.
///
/// Left column (flexible): `HubPageHeader` on the shared keyline, one
/// bounded object at a fixed height (drop zone,
/// tap pad, capture readout, URL entry), then a flat list that fills the rest.
/// Right column (fixed `inspectorWidth`, sidebar chrome material, hairline seam): the
/// page's options as labelled groups, and the primary action pinned at the
/// bottom so it sits in the same place on every tool. The action slot also owns
/// the page's Return and Esc keys (`primaryKey`, `cancelKey`).
public struct HubInspectorPage<Header: View, Live: View, Primary: View, List: View, Inspector: View, Action: View>: View {
    public static var inspectorWidth: CGFloat { HubDesignSystem.Size.chromeRailWidth }
    public static var primaryHeight: CGFloat { 168 }
    /// Matches the tools sidebar (`ToolSidebarView`): 12pt inset, 16pt between groups.
    public static var inspectorInset: CGFloat { 12 }
    /// Mirrors the sidebar: row bottom → next caption top is 6 + 14 = 20.
    public static var groupSpacing: CGFloat { 20 }

    @Environment(\.hubTitleRowInset) private var titleRowInset
    @Environment(\.hubToolIsActive) private var isVisiblePage
    @Environment(\.hubShellEscape) private var shellEscape

    private let header: Header
    private let live: Live
    private let primary: Primary
    private let list: List
    private let inspector: Inspector
    private let action: Action
    private let primaryKey: HubPageKey?
    private let cancelKey: HubPageKey?

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder live: () -> Live,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder list: () -> List,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder action: () -> Action,
        primaryKey: HubPageKey? = nil,
        cancelKey: HubPageKey? = nil
    ) {
        self.header = header()
        self.live = live()
        self.primary = primary()
        self.list = list()
        self.inspector = inspector()
        self.action = action()
        self.primaryKey = primaryKey
        self.cancelKey = cancelKey
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                header
                primary
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.primaryHeight)
                // The list is the only part that grows, so it is the only part that
                // scrolls: header and the bounded object stay on their
                // keylines no matter how many rows exist (a queue or a stem run can
                // be dozens of rows, which otherwise pushes the whole window open).
                ScrollView {
                    VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                        live
                        list
                    }
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
                    // Label keyline 120 (under the 56pt title band), first control at
                    // 144 — mirrors the sidebar's first caption + row (measured).
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
                .background { pageKeyButtons }
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

    /// Hidden buttons that give the page's keys their shortcuts; a disabled key, or
    /// any key of a page you left, installs none. Without an enabled cancel key the
    /// visible page binds the shell's Esc instead: AppKit never gives a plain Esc to
    /// the Edit ▸ Cancel menu item while the window is key (`HubShellEscape`).
    @ViewBuilder
    private var pageKeyButtons: some View {
        if let key = HubPageKey.installed(primaryKey, onVisiblePage: isVisiblePage) {
            Button(key.title, action: key.perform)
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
        }
        if let key = HubPageKey.installed(cancelKey, onVisiblePage: isVisiblePage) {
            Button(key.title, action: key.perform)
                .keyboardShortcut(.cancelAction)
                .hidden()
                .accessibilityHidden(true)
        } else if isVisiblePage, let shellEscape {
            HubShellEscapeButton(escape: shellEscape)
        }
    }
}

/// The shell's Esc as the visible page's cancel button, bound only while there is
/// a job to cancel, as the Edit ▸ Cancel item is enabled only then. Only this view
/// observes the job list, so a job's progress redraws it and not the page.
private struct HubShellEscapeButton: View {
    @ObservedObject private var jobStatusCenter: ShellJobStatusCenter
    private let escape: HubShellEscape

    init(escape: HubShellEscape) {
        self.escape = escape
        self.jobStatusCenter = escape.jobStatusCenter
    }

    var body: some View {
        if !escape.jobs.isEmpty {
            Button(CancelCopy.cancelOperation) { escape.cancel() }
                .keyboardShortcut(.cancelAction)
                .hidden()
                .accessibilityHidden(true)
        }
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
        // Same caption language as the sidebar sections (body-size, regular,
        // tertiary grey); label → control gap 8 lands the control on the
        // sidebar's nav-row keyline.
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .frame(height: 16)
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
