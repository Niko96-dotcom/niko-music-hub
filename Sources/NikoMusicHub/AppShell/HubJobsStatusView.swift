import AppCore
import SwiftUI

/// Production-shell running-job row. Lives in the sidebar, outside the tool pane cache.
struct HubJobsStatusView: View {
    @ObservedObject var center: ShellJobStatusCenter
    @State private var showJobList = false

    var body: some View {
        Group {
            if center.jobs.isEmpty {
                EmptyView()
            } else if center.jobs.count == 1, let job = center.jobs.first {
                singleJobRow(job)
            } else {
                multipleJobsRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub_jobs_status")
    }

    private func singleJobRow(_ job: ShellJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.displayLine)
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let cancelID = job.cancelActionID {
                HubLabeledButton(
                    icon: "stop.fill",
                    label: ShellJobStatusCopy.cancel,
                    style: .secondary,
                    help: help(for: job)
                ) {
                    center.cancel(id: cancelID)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(job.displayLine)
    }

    private var multipleJobsRow: some View {
        Button {
            showJobList.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: HubDesignSystem.Size.sidebarIconFrame)
                Text(center.compactCopy)
                    .font(HubDesignSystem.Typography.body())
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Spacing.navRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(center.compactCopy)
        .accessibilityLabel(center.compactCopy)
        .accessibilityHint("Shows each running job and Cancel.")
        .popover(isPresented: $showJobList, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(center.jobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.displayLine)
                            .font(HubDesignSystem.Typography.bodySmall())
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let cancelID = job.cancelActionID {
                            HubLabeledButton(
                                icon: "stop.fill",
                                label: ShellJobStatusCopy.cancel,
                                style: .secondary,
                                help: help(for: job)
                            ) {
                                center.cancel(id: cancelID)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(width: 260)
        }
    }

    private func help(for job: ShellJobStatus) -> String {
        if job.id == ShellJobExtraSourceID.converter {
            return ShellJobStatusCopy.converterCancelHelp
        }
        return ShellJobStatusCopy.cancel
    }
}
