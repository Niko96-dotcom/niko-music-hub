import AppCore
import SwiftUI

public struct BPMTapperView: View {
    let context: ToolContext

    /// Owned by the feature session (`viewModel(for:)`), not by this view.
    @ObservedObject private var viewModel: BPMTapperViewModel
    @FocusState private var tapSurfaceFocused: Bool
    @State private var clearHistoryConfirmationVisible = false
    @State private var copiedHistoryEntryID: UUID?
    @State private var tapSurfacePressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        context: ToolContext,
        viewModel: BPMTapperViewModel = BPMTapperViewModel()
    ) {
        self.context = context
        self.viewModel = viewModel
    }

    public var body: some View {
        HubInspectorPage(
            header: { header },
            live: {
                if viewModel.copyConfirmation != nil || viewModel.saveConfirmation != nil || viewModel.errorText != nil {
                    inlineMessages
                } else {
                    EmptyView()
                }
            },
            primary: { tapCard },
            list: { historySection },
            inspector: { EmptyView() },
            action: { tapActions }
        )
        .onAppear {
            try? viewModel.loadHistory()
            tapSurfaceFocused = true
        }
        .alert(
            "Clear History?",
            isPresented: $clearHistoryConfirmationVisible
        ) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Clear History", role: .destructive) {
                viewModel.clearHistory()
            }
        } message: {
            Text(viewModel.hasCorruptHistory
                ? "Sets aside unreadable history and clears the list. The current tap run is kept."
                : "Removes saved BPM history. The current tap run is kept.")
        }
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "BPM Tapper",
            statusText: viewModel.statusText,
            statusColor: statusColor
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var readoutRows: some View {
        HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(displayedBPMText)
                .font(HubDesignSystem.Typography.readout())
                .accessibilityLabel(bpmReadoutAnnouncement.label)
                .accessibilityValue(bpmReadoutAnnouncement.value)

            Text("BPM")
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }

        Text(progressText)
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Palette.textTertiary)

        if let originalContextText {
            Text(originalContextText)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }


    private var tapCard: some View {
        Button(action: {
            animateTapPress()
            viewModel.recordTap()
            tapSurfaceFocused = true
        }) {
            VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                readoutRows

                Text("Tap or press Space")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            .padding(HubDesignSystem.Spacing.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hubCard(
                cornerRadius: HubDesignSystem.Radius.card,
                state: tapSurfacePressed ? .pressed : .normal,
                interactive: true
            )
            .scaleEffect(tapSurfacePressed ? 0.98 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        // No system-blue ring around the pad; the quiet ring below is the
        // keyboard affordance (only when navigating by keyboard).
        .focusEffectDisabled()
        .focused($tapSurfaceFocused)
        .overlay {
            if tapSurfaceFocused, NSApp.isFullKeyboardAccessEnabled {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card, style: .continuous)
                    .strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onKeyPress(.space) {
            animateTapPress()
            viewModel.recordTap()
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.resetTaps()
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tap Tempo")
        .accessibilityValue(viewModel.statusText)
        .accessibilityHint("Space taps tempo. Escape resets the current run.")
    }

    private var tapActions: some View {
        Group {
            HubLabeledButton(
                icon: "bookmark.fill",
                label: "Save BPM",
                style: .primary,
                isEnabled: viewModel.displayedBPM != nil,
                expands: true
            ) {
                copiedHistoryEntryID = nil
                viewModel.saveDisplayedBPM()
            }

            HubLabeledButton(
                icon: "doc.on.doc",
                label: "Copy BPM",
                style: .ghost,
                isEnabled: viewModel.displayedBPM != nil,
                expands: true
            ) {
                copiedHistoryEntryID = nil
                viewModel.copyDisplayedBPM()
            }

            HubLabeledButton(
                icon: "arrow.counterclockwise",
                label: "Reset",
                style: .ghost,
                isEnabled: viewModel.hasStartedRun,
                expands: true
            ) {
                viewModel.resetTaps()
                tapSurfaceFocused = true
            }
        }
    }

    private var inlineMessages: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            if let copyConfirmation = viewModel.copyConfirmation {
                Text(copyConfirmation)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Colors.success)
            }

            if let saveConfirmation = viewModel.saveConfirmation {
                Text(saveConfirmation)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Colors.success)
            }

            if let errorText = viewModel.errorText {
                if viewModel.hasCorruptHistory {
                    let card = AppErrorCard(
                        category: .conversionFile,
                        label: "Saved BPM History Is Unreadable",
                        icon: "externaldrive.badge.xmark",
                        body: errorText,
                        recoveryActions: [
                            AppErrorCard.RecoveryAction(
                                label: "Clear History",
                                style: .destructive,
                                action: .clearHistory
                            )
                        ]
                    )
                    StandardErrorCard(card: card) { action in
                        // Corrupt bytes never Retry: the only recovery is the
                        // existing Clear History confirmation (never direct).
                        if action == .clearHistory {
                            clearHistoryConfirmationVisible = true
                        }
                    }
                } else {
                    let card = AppErrorCard(
                        category: .conversionFile,
                        label: "Could Not Save BPM",
                        icon: "externaldrive.badge.xmark",
                        body: errorText,
                        recoveryActions: [
                            AppErrorCard.RecoveryAction(
                                label: "Try Again",
                                style: .primary,
                                action: .tryAgain
                            )
                        ]
                    )
                    StandardErrorCard(card: card) { action in
                        // NMH-043: every shown action must do something. The card
                        // offers Try Again only; it retries the failed storage work.
                        if action == .tryAgain {
                            viewModel.retryAfterStorageError()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var historySection: some View {
        HubListSection("Recent Tempos", count: viewModel.historyEntries.count, trailing: {
            // The unreadable-history card supplies this action beside its
            // explanation. Keep one Clear control in that recovery state.
            if !viewModel.hasCorruptHistory {
                HubLabeledButton(
                    icon: "trash",
                    label: "Clear History",
                    style: .ghost,
                    role: .destructive,
                    isEnabled: !viewModel.historyEntries.isEmpty
                ) {
                    copiedHistoryEntryID = nil
                    clearHistoryConfirmationVisible = true
                }
            }
        }) {
            if viewModel.historyEntries.isEmpty {
                HubListEmpty("No saved tempos")
            } else {
                ForEach(viewModel.historyEntries) { entry in
                    historyRow(entry)
                }
            }
        }
    }

    private func historyRow(_ entry: BPMHistoryEntry) -> some View {
        HubListRow {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBPM(entry.bpm))
                        .font(HubDesignSystem.Typography.body())
                        .fontWeight(.semibold)
                        .monospacedDigit()

                    Text("BPM")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }

                Text(historyContext(for: entry))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)

                HubIconButton(
                    systemImage: "doc.on.doc",
                    accessibilityLabel: "Copy saved BPM",
                    help: "Copy this saved tempo"
                ) {
                    viewModel.copySavedBPM(entry)
                    copiedHistoryEntryID = entry.id
                }

                if copiedHistoryEntryID == entry.id {
                    Text("BPM copied")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Colors.success)
                }
            }
        }
    }

    private func animateTapPress() {
        guard !reduceMotion else { return }
        tapSurfacePressed = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            tapSurfacePressed = false
        }
    }

    private var displayedBPMText: String {
        guard let displayedBPM = viewModel.displayedBPM else {
            return "--"
        }
        return formatBPM(displayedBPM)
    }

    private var bpmReadoutAnnouncement: BPMReadoutAnnouncement {
        BPMReadoutAnnouncement(displayedBPMText: displayedBPMText)
    }

    private var progressText: String {
        switch viewModel.tapCount {
        case 0:
            return "0 taps"
        case 1:
            return "1 tap"
        default:
            return "\(viewModel.tapCount) taps"
        }
    }

    private var statusColor: Color {
        switch viewModel.statusKind {
        case .longPauseReset, .outlierIgnored:
            return HubDesignSystem.Colors.warning
        default:
            return .secondary
        }
    }


    private var originalContextText: String? {
        guard viewModel.adjustment != .original,
              let rawBPM = viewModel.rawBPM else {
            return nil
        }

        return "Original \(formatBPM(rawBPM)) BPM"
    }

    private func historyContext(for entry: BPMHistoryEntry) -> String {
        "\(entry.timestamp.formatted(date: .omitted, time: .shortened)) - \(entry.adjustment.displayName) from \(formatBPM(entry.rawTappedBPM)) BPM"
    }

    private func formatBPM(_ bpm: Double) -> String {
        String(Int(bpm.rounded()))
    }
}
