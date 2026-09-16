import AppCore
import NikoMusicCore
import SwiftUI

/// Archive analytics: an honest picture of finishing habits, derived from
/// real project-file dates and the recorded status history — no manual logs.
struct ArchiveAnalyticsView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
            HubLabeledButton(
                icon: "chevron.backward",
                label: "Board",
                style: .ghost,
                help: "Back to the board (Esc)"
            ) {
                viewModel.viewMode = .board
            }

            header

            if let snapshot = viewModel.analyticsSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                        overviewRow(snapshot.overview)
                        monthlySection(snapshot.monthlyActivity)
                        stageSection(snapshot.stageDistribution)
                        dwellSection(snapshot)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { viewModel.refreshAnalytics() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Analytics")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            Text("Built from your project file dates and status changes.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    // MARK: - Overview

    private func overviewRow(_ overview: ArchiveAnalyticsSnapshot.Overview) -> some View {
        HStack(alignment: .top, spacing: 28) {
            statItem(value: "\(overview.totalSongs)", caption: "songs")
            statItem(value: "\(overview.inProgress)", caption: "in progress")
            statItem(value: "\(overview.finished)", caption: "done")
            if let rate = overview.finishRate {
                statItem(value: "\(Int((rate * 100).rounded()))%", caption: "finish rate")
            }
            statItem(
                value: "\(overview.quiet)",
                caption: "quiet 30d+",
                tint: overview.quiet > 0 ? HubDesignSystem.Palette.warning : nil
            )
            statItem(value: "\(overview.noStatus)", caption: "no status")
            Spacer(minLength: 0)
        }
    }

    private func statItem(value: String, caption: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? HubDesignSystem.Palette.textPrimary)
            Text(caption)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }

    // MARK: - Monthly activity

    private func monthlySection(_ months: [ArchiveAnalyticsSnapshot.MonthActivity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Project saves per month")
            Text("Bar chart of project saves by month for the last 12 months.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)

            if months.allSatisfy({ $0.versionCount == 0 }) {
                emptyHint("No project file activity in the last \(months.count) months.")
            } else {
                let peak = max(months.map(\.versionCount).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                        VStack(spacing: 4) {
                            Text("\(month.versionCount)")
                                .font(HubDesignSystem.Typography.caption())
                                .monospacedDigit()
                                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                                .accessibilityHidden(true)
                            Capsule(style: .continuous)
                                .fill(
                                    month.versionCount > 0
                                        ? HubDesignSystem.Palette.accent.opacity(0.7)
                                        : HubDesignSystem.Palette.textPrimary.opacity(0.08)
                                )
                                .frame(height: barHeight(month.versionCount, peak: peak))
                                .frame(maxWidth: .infinity)
                            Text(Self.monthLabel(for: month.monthStart, index: index, count: months.count))
                                .font(HubDesignSystem.Typography.micro())
                                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        }
                        .help("\(month.versionCount) saves · \(month.songCount) songs")
                        .accessibilityElement()
                        .accessibilityLabel(
                            "\(Self.monthFormatter.string(from: month.monthStart)): \(month.versionCount) saves across \(month.songCount) songs"
                        )
                    }
                }
                .frame(maxHeight: 96, alignment: .bottom)
            }
        }
    }

    private func barHeight(_ count: Int, peak: Int) -> CGFloat {
        guard count > 0 else { return 3 }
        return max(6, CGFloat(count) / CGFloat(peak) * 84)
    }

    // MARK: - Stage distribution

    private func stageSection(_ stages: [ArchiveAnalyticsSnapshot.StageCount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Where songs sit")

            let peak = max(stages.map(\.count).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(stages) { stage in
                    stageBar(
                        label: stage.status.shortTitle,
                        tint: stage.status.archiveTint,
                        fraction: Double(stage.count) / Double(peak),
                        trailing: "\(stage.count)",
                        help: "\(stage.count) songs in \(stage.status.displayTitle)"
                    )
                }
            }
        }
    }

    // MARK: - Stage dwell

    @ViewBuilder
    private func dwellSection(_ snapshot: ArchiveAnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader("Time spent per stage")

            if snapshot.stageDwell.isEmpty {
                emptyHint("Builds up as songs change status — tracking since \(historyStartLabel(snapshot)).")
            } else {
                let peak = max(snapshot.stageDwell.map(\.averageDays).max() ?? 1, 0.01)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.stageDwell) { dwell in
                        stageBar(
                            label: dwell.status.shortTitle,
                            tint: dwell.status.archiveTint,
                            fraction: dwell.averageDays / peak,
                            trailing: dwellLabel(dwell.averageDays),
                            help: "\(dwell.status.displayTitle): average \(dwellLabel(dwell.averageDays)) across \(dwell.sampleCount) stays"
                        )
                    }
                }
                Text("Average stay per stage, from recorded status changes since \(historyStartLabel(snapshot)).")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }
        }
    }

    private func dwellLabel(_ days: Double) -> String {
        if days < 1 {
            let hours = days * 24
            return hours < 1 ? "<1 h" : "\(Int(hours.rounded())) h"
        }
        return String(format: "%.1f d", days)
    }

    private func historyStartLabel(_ snapshot: ArchiveAnalyticsSnapshot) -> String {
        guard let start = snapshot.earliestHistoryEntry else { return "today" }
        return Self.dayFormatter.string(from: start)
    }

    // MARK: - Shared pieces

    private func stageBar(
        label: String,
        tint: Color,
        fraction: Double,
        trailing: String,
        help: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(width: 56, alignment: .leading)
            ArchiveAnalyticsFractionBar(tint: tint, fraction: fraction)
                .frame(height: 8)
            Text(trailing)
                .font(HubDesignSystem.Typography.caption())
                .monospacedDigit()
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
        .help(help)
        .accessibilityElement()
        .accessibilityLabel(help)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(HubDesignSystem.Typography.caption())
            .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    /// Visible X-axis label: year on the first and last month only (NMH-050).
    static func monthLabel(for date: Date, index: Int, count: Int) -> String {
        if index == 0 || index == count - 1 {
            return monthYearFormatter.string(from: date)
        }
        return monthFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct ArchiveAnalyticsFractionBar: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let tint: Color
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: layoutDirection == .rightToLeft ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(HubDesignSystem.Palette.textPrimary.opacity(0.06))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.65))
                    .frame(width: max(4, proxy.size.width * fraction.clamped01))
            }
        }
    }
}

private extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

#if DEBUG
#Preview("Analytics bars RTL") {
    VStack(alignment: .leading, spacing: 8) {
        ArchiveAnalyticsFractionBar(tint: HubDesignSystem.Palette.accent, fraction: 0.7)
            .frame(height: 8)
        ArchiveAnalyticsFractionBar(tint: HubDesignSystem.Palette.warning, fraction: 0.35)
            .frame(height: 8)
    }
    .padding()
    .frame(width: 280)
    .environment(\.layoutDirection, .rightToLeft)
}
#endif
