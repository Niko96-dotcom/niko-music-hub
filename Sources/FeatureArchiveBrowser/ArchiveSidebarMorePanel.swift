import SwiftUI

/// Health, collaborators, intelligence, and diagnostics folded into the sidebar footer.
struct ArchiveSidebarMorePanel: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        let health = viewModel.sidebarHealthContext
        DisclosureGroup(isExpanded: $viewModel.sidebarMorePanelExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ArchiveHealthReportView(report: health.report, compact: true)
                ArchiveCollaboratorAddressBookView(viewModel: viewModel)
                ArchiveIntelligencePanelView(viewModel: viewModel)
                if let diagnostics = viewModel.scanDiagnostics {
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
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                Text(health.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
