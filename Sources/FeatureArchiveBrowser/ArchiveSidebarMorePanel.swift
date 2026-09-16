import AppCore
import SwiftUI

/// Health, collaborators, intelligence, and diagnostics tucked under a collapsible Library section.
struct ArchiveSidebarMorePanel: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Binding var isExpanded: Bool
    @ObservedObject var sidebarUI: ArchiveSidebarUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                animateDisclosure {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                    Text("Library")
                        .font(HubDesignSystem.Typography.caption())
                        .tracking(0.7)
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ForwardDisclosureChevron(isExpanded: isExpanded)
                }
                .padding(.top, HubDesignSystem.Spacing.sectionHeaderTop)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Library")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                libraryRow(
                    title: "Scan Health",
                    systemImage: "chart.bar.doc.horizontal",
                    isExpanded: $sidebarUI.healthRowExpanded
                ) {
                    ArchiveHealthReportView(report: viewModel.sidebarHealthContext.report, compact: true)
                }

                libraryRow(
                    title: "Project Vault",
                    systemImage: "archivebox",
                    isExpanded: $sidebarUI.vaultRowExpanded
                ) {
                    SidebarProjectVaultStatusView(
                        health: viewModel.projectVaultHealth,
                        openVaultSettings: openVaultSettings
                    )
                }

                libraryRow(
                    title: "Collaborators",
                    systemImage: "person.2",
                    isExpanded: $sidebarUI.collaboratorsRowExpanded
                ) {
                    ArchiveCollaboratorAddressBookView(viewModel: viewModel)
                }

                libraryRow(
                    title: "Intelligence",
                    systemImage: "sparkles",
                    isExpanded: $sidebarUI.intelligenceRowExpanded
                ) {
                    ArchiveIntelligencePanelView(viewModel: viewModel)
                }

                if let diagnostics = viewModel.scanDiagnostics {
                    libraryRow(
                        title: "Diagnostics",
                        systemImage: "stethoscope",
                        isExpanded: $sidebarUI.diagnosticsRowExpanded
                    ) {
                        ScrollView {
                            ArchiveDiagnosticsPanelView(
                                viewModel: viewModel,
                                diagnostics: diagnostics,
                                selectedSong: viewModel.selectedSong,
                                searchContext: viewModel.activeSearchExportContext(),
                                skippedSearchContext: viewModel.activeSkippedSearchExportContext()
                            )
                        }
                        .frame(maxHeight: 140)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func libraryRow<Content: View>(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        // Whole-row toggle: a native DisclosureGroup only toggles on its tiny chevron,
        // which makes these rows feel dead. The entire nav row is the tap target.
        VStack(alignment: .leading, spacing: 0) {
            Button {
                animateDisclosure {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .frame(width: HubDesignSystem.Size.sidebarIconFrame)
                    Text(title)
                        .font(HubDesignSystem.Typography.body())
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    Spacer(minLength: 0)
                    ForwardDisclosureChevron(isExpanded: isExpanded.wrappedValue)
                }
                .padding(.horizontal, 4)
                .frame(height: HubDesignSystem.Spacing.navRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")

            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 4)
                    .padding(.leading, HubDesignSystem.Size.sidebarIconFrame + HubDesignSystem.Spacing.controlGap)
            }
        }
    }

    private func animateDisclosure(_ updates: @escaping () -> Void) {
        let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
        if duration == 0 {
            updates()
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                updates()
            }
        }
    }

    /// NMH-057: deep-link to the Vault Settings pane. The pane notification
    /// selects Vault when Settings is already open; `openSettings()` opens it
    /// otherwise, and the deferred repost selects Vault once the fresh
    /// Settings window has mounted its pane observer.
    private func openVaultSettings() {
        NotificationCenter.default.post(name: .hubOpenSettingsPane, object: HubSettingsPane.vault)
        openSettings()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .hubOpenSettingsPane, object: HubSettingsPane.vault)
        }
    }
}

/// NMH-057: Project Vault provider status. Scan counts live under Scan Health;
/// this row reports only the vault disk/provider state and links to Settings.
private struct SidebarProjectVaultStatusView: View {
    let health: ProjectVaultHealth
    let openVaultSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                ProjectVaultHealthCopy.archiveSidebarLine(health),
                systemImage: health.providerStatus == .offline
                    ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark"
            )
            .font(HubDesignSystem.Typography.caption())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HubLabeledButton(
                icon: "gearshape",
                label: "Open Vault Settings",
                style: .ghost,
                help: "Open Project Vault settings"
            ) {
                openVaultSettings()
            }
        }
        .padding(6)
    }
}

/// Collapsed points forward (`chevron.forward`); expanded rotates down in both directions.
private struct ForwardDisclosureChevron: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            .rotationEffect(.degrees(isExpanded ? expandAngle : 0))
    }

    private var expandAngle: Double {
        layoutDirection == .rightToLeft ? -90 : 90
    }
}

#if DEBUG
#Preview("Library chevrons RTL") {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Library")
            Spacer(minLength: 0)
            ForwardDisclosureChevron(isExpanded: false)
        }
        HStack {
            Text("Scan Health")
            Spacer(minLength: 0)
            ForwardDisclosureChevron(isExpanded: true)
        }
    }
    .padding()
    .frame(width: 220)
    .environment(\.layoutDirection, .rightToLeft)
}
#endif
