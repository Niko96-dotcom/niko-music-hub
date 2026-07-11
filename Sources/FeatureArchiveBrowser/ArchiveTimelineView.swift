import AppCore
import NikoMusicCore
import SwiftUI

/// Archive timeline: months of real CPR activity, derived from scanned file
/// dates — no manual upkeep. Respects the sidebar's current shelf/search/filters.
struct ArchiveTimelineView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    private var months: [ArchiveTimelineMonth] {
        ArchiveTimelineProjection.months(from: viewModel.filteredSongs)
    }

    var body: some View {
        let months = self.months
        VStack(alignment: .leading, spacing: 0) {
            header(months: months)

            if months.isEmpty {
                emptyState
                    .padding(.top, 14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(months) { month in
                            monthSection(month)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(months: [ArchiveTimelineMonth]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Timeline")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Spacer(minLength: 4)

            if !months.isEmpty {
                Text("\(months.reduce(0) { $0 + $1.versionCount }) project versions · \(months.count) months")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .top)
    }

    private func monthSection(_ month: ArchiveTimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.monthFormatter.string(from: month.monthStart))
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                Text("\(month.entries.count) songs · \(month.versionCount) versions")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(month.entries) { entry in
                    ArchiveTimelineEntryRow(
                        entry: entry,
                        isSelected: viewModel.selectedSong?.id == entry.song.id,
                        onSelect: { viewModel.selectSong(entry.song) }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No activity to show", systemImage: "calendar.day.timeline.left")
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            Text("The timeline is built from Cubase project file dates for the songs in the current list. Try clearing filters or rescanning.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

private struct ArchiveTimelineEntryRow: View {
    let entry: ArchiveTimelineEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.song.effectiveDisplayTitle)
                .font(HubDesignSystem.Typography.body().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .lineLimit(1)

            if let status = entry.song.workflowStatus {
                ArchiveWorkflowStatusPill(status: status, compact: true)
            }

            Spacer(minLength: 8)

            versionDots

            Text(Self.dayFormatter.string(from: entry.latestActivity))
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .help("\(entry.versionCount) project version\(entry.versionCount == 1 ? "" : "s") this month — click to open")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.song.effectiveDisplayTitle), \(entry.versionCount) versions")
    }

    private var versionDots: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< min(entry.versionCount, 8), id: \.self) { _ in
                Circle()
                    .fill(HubDesignSystem.Palette.accent.opacity(0.75))
                    .frame(width: 5, height: 5)
            }
            if entry.versionCount > 8 {
                Text("+\(entry.versionCount - 8)")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }
        }
    }

    private var rowFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? Color.white.opacity(0.05) : Color.clear
    }
}
