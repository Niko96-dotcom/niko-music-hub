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
        ScrollView {
            VStack(spacing: HubDesignSystem.Spacing.section) {
                header
                tapWorkflow
                historySection
            }
            .hubToolContentPadding()
            .frame(maxWidth: HubToolLayout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
        VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            Text("BPM Tapper")
                .font(HubDesignSystem.Typography.screenTitle())

            Text(viewModel.statusText)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560)
    }

    private var tapWorkflow: some View {
        VStack(spacing: HubDesignSystem.Spacing.panel) {
            bpmReadout
            adjustmentPicker
            tapSurface
            actionRow
        }
        .frame(maxWidth: 560)
    }

    private var bpmReadout: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayedBPMText)
                    .font(HubDesignSystem.Typography.display())
                    .monospacedDigit()
                    .accessibilityLabel("Current BPM")

                Text("BPM")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }

            Text(progressText)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(.tertiary)

            if let originalContextText {
                Text(originalContextText)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 80)
        .frame(maxWidth: .infinity)
    }

    private var adjustmentPicker: some View {
        Picker("Adjustment", selection: adjustmentBinding) {
            Text("Original")
                .tag(BPMAdjustment.original)
            Text("Half-Time")
                .tag(BPMAdjustment.halfTime)
            Text("Double-Time")
                .tag(BPMAdjustment.doubleTime)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
        .disabled(viewModel.displayedBPM == nil)
    }

    private var tapSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card, style: .continuous)
                        .strokeBorder(
                            tapSurfaceFocused ? HubDesignSystem.Colors.accent : HubDesignSystem.glassStroke,
                            lineWidth: tapSurfaceFocused ? 2 : 0.5
                        )
                }

            VStack(spacing: 8) {
                Text("Tap Tempo")
                    .font(.system(size: 18, weight: .semibold))

                Text("Tap or press Space")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxWidth: 560, minHeight: 160)
        .scaleEffect(tapSurfacePressed ? 0.98 : 1)
        .contentShape(Rectangle())
        .focusable()
        .focused($tapSurfaceFocused)
        .onTapGesture {
            animateTapPress()
            viewModel.recordTap()
            tapSurfaceFocused = true
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
            Divider()
                .overlay(HubDesignSystem.Colors.separator)

            Text("Recent Tempos")
                .font(HubDesignSystem.Typography.sectionTitle())
                .frame(maxWidth: .infinity)

            if viewModel.historyEntries.isEmpty {
                VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                    Text("No tempos saved yet")
                        .font(HubDesignSystem.Typography.body())
                        .fontWeight(.semibold)

                    Text("Saved BPM results will appear here with their time and adjustment mode. Tap a tempo, then Save BPM to keep it for this session.")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)
            } else {
                VStack(spacing: HubDesignSystem.Spacing.cardGap) {
                    ForEach(viewModel.historyEntries) { entry in
                        historyRow(entry)
                    }
                }
                .frame(maxWidth: 560)
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
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ entry: BPMHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBPM(entry.bpm))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()

                    Text("BPM")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(.secondary)
                }

                Text(historyContext(for: entry))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
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
        .padding(12)
        .hubGlassCard()
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
