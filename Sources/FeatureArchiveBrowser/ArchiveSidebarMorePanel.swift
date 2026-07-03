import AppCore
import SwiftUI

/// Health, collaborators, intelligence, and diagnostics as a discoverable labeled section
/// (reference: "Library" section header + labeled rows, not a bare disclosure triangle).
/// Every function is visible with a text label per IA — no hidden chrome-only affordances.
struct ArchiveSidebarMorePanel: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Binding var isExpanded: Bool
    @ObservedObject var sidebarUI: ArchiveSidebarUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubSectionHeader("Library")

            libraryRow(
                title: "Archive Health",
                systemImage: "chart.bar.doc.horizontal",
                isExpanded: $sidebarUI.healthRowExpanded
            ) {
                ArchiveHealthReportView(report: viewModel.sidebarHealthContext.report, compact: true)
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
                            diagnostics: diagnostics,
                            selectedSong: viewModel.selectedSong,
                            searchContext: viewModel.activeSearchExportContext(),
                            skippedSearchContext: viewModel.activeSkippedSearchExportContext()
                        ) {
                            viewModel.performExport { try viewModel.exportDiagnostics() }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
        .onAppear { isExpanded = true }
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
                withAnimation(.easeInOut(duration: HubDesignSystem.Motion.short)) {
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
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
}
