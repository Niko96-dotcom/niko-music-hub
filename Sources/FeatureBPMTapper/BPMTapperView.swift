import AppCore
import SwiftUI

public struct BPMTapperView: View {
    let context: ToolContext

    @StateObject private var viewModel: BPMTapperViewModel
    @FocusState private var tapSurfaceFocused: Bool
    @State private var clearHistoryConfirmationVisible = false
    @State private var copiedHistoryEntryID: UUID?

    public init(
        context: ToolContext,
        viewModel: BPMTapperViewModel = BPMTapperViewModel()
    ) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                tapWorkflow
                historySection
            }
            .hubToolContentPadding()
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("BPM Tapper", systemImage: "metronome")
                .font(HubDesignSystem.Typography.sectionTitle())

            Text(viewModel.statusText)
                .font(.system(size: 13))
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var tapWorkflow: some View {
        VStack(alignment: .leading, spacing: 16) {
            bpmReadout
            adjustmentPicker
            tapSurface
            actionRow
        }
        .frame(minWidth: 320, idealWidth: 440, maxWidth: 560, alignment: .leading)
    }

    private var bpmReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(displayedBPMText)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Current BPM")

                Text("BPM")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(progressText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let originalContextText {
                Text(originalContextText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 68, alignment: .leading)
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
                            tapSurfaceFocused ? Color.accentColor : HubDesignSystem.glassStroke,
                            lineWidth: tapSurfaceFocused ? 2 : 0.5
                        )
                }

            VStack(spacing: 8) {
                Text("Tap Tempo")
                    .font(.system(size: 16, weight: .semibold))

                Text(viewModel.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .frame(minWidth: 320, idealWidth: 440, minHeight: 180, idealHeight: 220)
        .contentShape(Rectangle())
        .focusable()
        .focused($tapSurfaceFocused)
        .onTapGesture {
            viewModel.recordTap()
            tapSurfaceFocused = true
        }
        .onKeyPress(.space) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HubIconButton(
                    systemImage: "doc.on.doc",
                    accessibilityLabel: "Copy BPM",
                    help: "Copy current BPM to clipboard",
                    isEnabled: viewModel.displayedBPM != nil
                ) {
                    copiedHistoryEntryID = nil
                    viewModel.copyDisplayedBPM()
                }

                HubIconButton(
                    systemImage: "bookmark.fill",
                    accessibilityLabel: "Save BPM",
                    help: "Save current BPM to history",
                    prominent: true,
                    isEnabled: viewModel.displayedBPM != nil
                ) {
                    copiedHistoryEntryID = nil
                    viewModel.saveDisplayedBPM()
                }

                HubIconButton(
                    systemImage: "arrow.counterclockwise",
                    accessibilityLabel: "Reset taps",
                    help: "Clear current tap run",
                    isEnabled: viewModel.hasStartedRun
                ) {
                    viewModel.resetTaps()
                    tapSurfaceFocused = true
                }
            }

            inlineMessages
        }
    }

    private var inlineMessages: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let copyConfirmation = viewModel.copyConfirmation {
                Text(copyConfirmation)
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }

            if let saveConfirmation = viewModel.saveConfirmation {
                Text(saveConfirmation)
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
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
        .frame(minHeight: 18, alignment: .leading)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            Text("Recent Tempos")
                .font(.system(size: 16, weight: .semibold))

            if viewModel.historyEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No tempos saved yet")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Saved BPM results will appear here with their time and adjustment mode. Tap a tempo, then Save BPM to keep it for this session.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.historyEntries) { entry in
                        historyRow(entry)
                    }
                }
            }

            HubIconButton(
                systemImage: "trash",
                accessibilityLabel: "Clear history",
                help: "Remove all saved tempos",
                role: .destructive,
                isEnabled: !viewModel.historyEntries.isEmpty
            ) {
                copiedHistoryEntryID = nil
                clearHistoryConfirmationVisible = true
            }
        }
        .frame(minWidth: 320, idealWidth: 440, maxWidth: 560, alignment: .leading)
    }

    private func historyRow(_ entry: BPMHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBPM(entry.bpm))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()

                    Text("BPM")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(historyContext(for: entry))
                    .font(.system(size: 12))
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
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .hubGlassCard()
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
            return .orange
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
