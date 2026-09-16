import AppCore
import SwiftUI

public struct BPMTapperView: View {
    let context: ToolContext

    @StateObject private var viewModel: BPMTapperViewModel
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
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HubToolPage {
            header
            tapWorkflow
            historySection
        }
        .onAppear {
            try? viewModel.loadHistory()
            tapSurfaceFocused = true
        }
        .confirmationDialog(
            "Clear History: Clear all saved tempos? This keeps the current tap run but removes saved BPM history.",
            isPresented: $clearHistoryConfirmationVisible,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                viewModel.clearHistory()
            }
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

    private var tapWorkflow: some View {
        VStack(spacing: HubDesignSystem.Spacing.panel) {
            bpmReadout
            adjustmentPicker
            tapSurface
            actionRow
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    private var bpmReadout: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayedBPMText)
                    .font(HubDesignSystem.Typography.display())
                    .monospacedDigit()
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
        .padding(HubDesignSystem.Spacing.cardPadding)
        .frame(minHeight: 94)
        .frame(maxWidth: .infinity)
    }

    private var adjustmentPicker: some View {
        HubChoiceChips("Adjustment", selection: adjustmentBinding, choices: [
            .init(BPMAdjustment.halfTime, label: "½"),
            .init(BPMAdjustment.original, label: "1×"),
            .init(BPMAdjustment.doubleTime, label: "2×"),
        ])
        .disabled(viewModel.displayedBPM == nil)
        .opacity(viewModel.displayedBPM == nil ? 0.45 : 1)
    }

    private var tapSurface: some View {
        Button(action: {
            animateTapPress()
            viewModel.recordTap()
            tapSurfaceFocused = true
        }) {
            VStack(spacing: 8) {
                Text("Tap Tempo")
                    .font(HubDesignSystem.Typography.sectionTitle())

                Text("Tap or press Space")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            .padding(HubDesignSystem.Spacing.cardPadding)
            .frame(maxWidth: 360, minHeight: 140)
            .hubCard(
                state: tapSurfacePressed ? .pressed : .normal,
                interactive: true
            )
            .scaleEffect(tapSurfacePressed ? 0.98 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($tapSurfaceFocused)
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

    private var actionRow: some View {
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "doc.on.doc",
                    label: "Copy BPM",
                    style: .secondary,
                    isEnabled: viewModel.displayedBPM != nil
                ) {
                    copiedHistoryEntryID = nil
                    viewModel.copyDisplayedBPM()
                }

                HubLabeledButton(
                    icon: "bookmark.fill",
                    label: "Save BPM",
                    style: .primary,
                    isEnabled: viewModel.displayedBPM != nil
                ) {
                    copiedHistoryEntryID = nil
                    viewModel.saveDisplayedBPM()
                }

                HubLabeledButton(
                    icon: "arrow.counterclockwise",
                    label: "Reset",
                    style: .secondary,
                    isEnabled: viewModel.hasStartedRun
                ) {
                    viewModel.resetTaps()
                    tapSurfaceFocused = true
                }
            }
            .frame(maxWidth: .infinity)

            inlineMessages
        }
    }

    private var inlineMessages: some View {
        VStack(spacing: 4) {
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

            if viewModel.errorText != nil {
                let card = AppErrorCard(
                    category: .conversionFile,
                    label: "Could Not Save BPM",
                    icon: "externaldrive.badge.xmark",
                    body: "Check available disk space. The output folder may be full or on a read-only volume.",
                    recoveryActions: [
                        AppErrorCard.RecoveryAction(
                            label: "Reveal in Finder",
                            style: .secondary,
                            action: .revealInFinder
                        ),
                        AppErrorCard.RecoveryAction(
                            label: "Try Again",
                            style: .primary,
                            action: .tryAgain
                        )
                    ]
                )
                StandardErrorCard(card: card)
            }
        }
        .frame(minHeight: 18)
        .frame(maxWidth: .infinity)
    }

    private var historySection: some View {
        VStack(spacing: HubDesignSystem.Spacing.panel) {
            HubSectionHeader("Recent Tempos", count: viewModel.historyEntries.count)
                .frame(maxWidth: HubToolLayout.maxContentWidth)

            if viewModel.historyEntries.isEmpty {
                VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                    Text("No tempos saved yet")
                        .font(HubDesignSystem.Typography.body())
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: HubToolLayout.maxContentWidth)
                .padding(HubDesignSystem.Spacing.cardPadding)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.historyEntries) { entry in
                        historyRow(entry)
                    }
                }
                .frame(maxWidth: HubToolLayout.maxContentWidth)
            }

            HubLabeledButton(
                icon: "trash",
                label: "Clear History",
                style: .secondary,
                role: .destructive,
                isEnabled: !viewModel.historyEntries.isEmpty
            ) {
                copiedHistoryEntryID = nil
                clearHistoryConfirmationVisible = true
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ entry: BPMHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBPM(entry.bpm))
                        .font(HubDesignSystem.Typography.sectionTitle())
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

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
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

    private var adjustmentBinding: Binding<BPMAdjustment> {
        Binding {
            viewModel.adjustment
        } set: { adjustment in
            viewModel.setAdjustment(adjustment)
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
