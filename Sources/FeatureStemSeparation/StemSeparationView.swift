import AppCore
import SwiftUI
import UniformTypeIdentifiers

public struct StemSeparationView: View {
    /// Owned by the feature session (`viewModel(for:)`), not by this view.
    @ObservedObject private var viewModel: StemSeparationViewModel
    @State private var isTargeted = false

    public init(viewModel: StemSeparationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HubInspectorPage(
            header: { header },
            live: { liveSection },
            primary: { intakeCard },
            list: { resultsSection },
            inspector: { inspectorGroups },
            action: { separationActions }
        )
        .onAppear { viewModel.onAppear() }
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "Stem Separation",
            statusText: viewModel.statusMessage,
            statusColor: viewModel.errorMessage == nil
                ? HubDesignSystem.Palette.textSecondary
                : HubDesignSystem.Colors.danger
        )
    }

    @ViewBuilder
    private var liveSection: some View {
        if viewModel.helperNeedsSetup {
            StandardErrorCard(card: Self.helperMissingCard()) { action in
                switch action {
                case .installHelperTools:
                    viewModel.openHubSettingsHelpers()
                case .chooseToolPath:
                    viewModel.chooseHelperPath()
                case .tryAgain:
                    viewModel.refreshHelperHealth()
                default:
                    break
                }
            }
        } else if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HubDesignSystem.Spacing.section)
                .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .error)
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Group {
                if viewModel.progress > 0 {
                    ProgressView(value: viewModel.progress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(HubDesignSystem.Colors.indicator)
            Text(viewModel.statusMessage)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    /// Intake card: the drop zone on top, the YouTube route below the divider.
    /// Compact spacing and caption sizes so both routes fit the 168pt slot.
    private var intakeCard: some View {
        VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            if viewModel.isRunning {
                progressRow
            } else {
                fileIntakeContent
                Divider()
                youtubeRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard(cornerRadius: HubDesignSystem.Radius.card, state: isTargeted ? .selected : .normal, interactive: true)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            // HAND-03: explicit fileURL intake via NSItemProvider.loadItem + handleDrop.
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) else {
                        continue
                    }
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                _ = viewModel.handleDrop(urls: urls)
            }
            return true
        }
    }

    private var fileIntakeContent: some View {
        ViewThatFits(in: .horizontal) {
            fileWideRow
            fileCompactRow
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop an audio file or choose a file to separate")
        .accessibilityHint("Accepts WAV, AIFF, MP3, M4A, or FLAC.")
    }

    /// Wide file route: description flexes, buttons keep intrinsic width.
    /// `fixedSize(horizontal:)` on the buttons keeps the horizontal candidate
    /// honest — it only fits when the full labels fit without wrapping.
    private var fileWideRow: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            fileDescription(isCompact: false)
            chooseFileButton
                .fixedSize(horizontal: true, vertical: false)
            if viewModel.droppedFileURL != nil {
                clearFileButton
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// Compact file route: same single row with a concise empty-state title.
    /// Buttons stay fixed-size so the basename truncates instead of the
    /// buttons wrapping; the full format hint stays in the visible caption
    /// and in the outer accessibility label/hint.
    private var fileCompactRow: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            fileDescription(isCompact: true)
            chooseFileButton
                .fixedSize(horizontal: true, vertical: false)
            if viewModel.droppedFileURL != nil {
                clearFileButton
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func fileDescription(isCompact: Bool) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            Image(systemName: viewModel.droppedFileURL == nil ? "arrow.down.document" : "waveform")
                .font(HubDesignSystem.Typography.body().weight(.medium))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            if let fileURL = viewModel.droppedFileURL {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(HubDesignSystem.Typography.body())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileURL.path)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(fileURL.path)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCompact ? "Drop audio file here" : "Drop an audio file here")
                        .font(HubDesignSystem.Typography.body())
                        .lineLimit(1)
                    Text("WAV, AIFF, MP3, M4A, FLAC")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooseFileButton: some View {
        HubLabeledButton(
            icon: "folder",
            label: "Choose File",
            style: .secondary,
            isEnabled: !viewModel.isRunning
        ) {
            viewModel.selectFile()
        }
    }

    private var clearFileButton: some View {
        HubLabeledButton(
            icon: "xmark",
            label: "Clear",
            style: .ghost,
            isEnabled: !viewModel.isRunning
        ) {
            viewModel.clearSelection()
        }
    }

    private var youtubeRow: some View {
        ViewThatFits(in: .horizontal) {
            youtubeWideRow
            youtubeCompactRows
        }
        .opacity(viewModel.isRunning ? 0.6 : 1)
        .disabled(viewModel.isRunning)
    }

    /// Wide YouTube route (unchanged design): field flexes, download button
    /// keeps intrinsic width so this candidate only fits when the full
    /// "Download & Separate" label fits without compression.
    private var youtubeWideRow: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "play.rectangle")
                .font(HubDesignSystem.Typography.body().weight(.medium))
                .foregroundStyle(.tertiary)

            HubQuietTextField("Paste a YouTube link…", text: $viewModel.youtubeURLText)
                .disabled(viewModel.isRunning)
                .onSubmit {
                    submitPrimaryStemJob()
                }

            HubLabeledButton(
                icon: "arrow.down.circle",
                label: "Download & Separate",
                style: viewModel.primaryIntake == .youtube ? .primary : .secondary,
                isEnabled: viewModel.canStartYouTube
            ) {
                viewModel.startYouTubeSeparation()
            }
            .fixedSize(horizontal: true, vertical: false)

            if !viewModel.youtubeURLText.isEmpty {
                HubIconButton(
                    systemImage: "xmark.circle.fill",
                    accessibilityLabel: "Clear YouTube URL",
                    help: "Clear the URL field",
                    isEnabled: !viewModel.isRunning
                ) {
                    viewModel.clearYouTubeURL()
                }
            }
        }
    }

    /// Compact YouTube route: URL field keeps ~full row on top, the download
    /// action sits on its own second row. Visible label shortens to
    /// "Download" with the full purpose kept in the accessibility label.
    private var youtubeCompactRows: some View {
        VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                Image(systemName: "play.rectangle")
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(.tertiary)

                HubQuietTextField("Paste a YouTube link…", text: $viewModel.youtubeURLText)
                    .disabled(viewModel.isRunning)
                    .onSubmit {
                        submitPrimaryStemJob()
                    }

                if !viewModel.youtubeURLText.isEmpty {
                    HubIconButton(
                        systemImage: "xmark.circle.fill",
                        accessibilityLabel: "Clear YouTube URL",
                        help: "Clear the URL field",
                        isEnabled: !viewModel.isRunning
                    ) {
                        viewModel.clearYouTubeURL()
                    }
                }
            }
            HubLabeledButton(
                icon: "arrow.down.circle",
                label: "Download",
                style: viewModel.primaryIntake == .youtube ? .primary : .secondary,
                isEnabled: viewModel.canStartYouTube
            ) {
                viewModel.startYouTubeSeparation()
            }
            .accessibilityLabel("Download & Separate")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var resultsSection: some View {
        ToolOutputShelf(
            title: "Results",
            items: viewModel.results,
            emptyText: "No stems yet",
            subtitle: { $0.metadata["displayName"] },
            onReveal: { viewModel.reveal(item: $0) }
        )
    }

    @ViewBuilder
    private var inspectorGroups: some View {
        HubInspectorGroup("Model") {
            HubSegmentedChoice(
                "Model",
                selection: $viewModel.selectedPreset,
                // Experimental 6-stem is hidden for now (owner decision 2026-09-17).
                options: viewModel.supportedPresets.filter { $0 != .experimental6 }.map {
                    .init($0, label: $0.displayName)
                }
            )
        }
        HubInspectorGroup("Output folder") {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                Text(viewModel.outputFolderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: HubDesignSystem.Spacing.navRowHeight)

                HubLabeledButton(
                    icon: "folder",
                    label: "Choose Output Folder",
                    style: .ghost,
                    isEnabled: !viewModel.isRunning
                ) {
                    viewModel.pickOutputFolder()
                }
            }
        }
    }

    private var separationActions: some View {
        Group {
            HubLabeledButton(
                icon: "waveform.path.ecg",
                label: "Start Separation",
                style: .primary,
                isEnabled: viewModel.canStart,
                expands: true
            ) {
                viewModel.startSeparation()
            }

            .background {
                if viewModel.canStart || viewModel.canStartYouTube {
                    Button(viewModel.canStartYouTube ? "Download & Separate" : "Start Separation") {
                        submitPrimaryStemJob()
                    }
                    .keyboardShortcut(.defaultAction)
                    .hidden()
                    .accessibilityHidden(true)
                }
            }

            if viewModel.canCancel {
                HubLabeledButton(
                    icon: "xmark",
                    label: "Cancel",
                    style: .ghost,
                    expands: true
                ) {
                    viewModel.cancelSeparation()
                }
                .background {
                    Button("Cancel") {
                        viewModel.cancelSeparation()
                    }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
        }
    }

    static func helperMissingCard() -> AppErrorCard {
        AppErrorCard(
            category: .helperTool,
            label: StemSeparationHelperCopy.missingLabel,
            icon: "tool.badge.xmark",
            body: StemSeparationHelperCopy.missingBody,
            recoveryActions: [
                AppErrorCard.RecoveryAction(label: "Install Tools", style: .primary, action: .installHelperTools),
                AppErrorCard.RecoveryAction(label: "Choose Path", style: .secondary, action: .chooseToolPath),
                AppErrorCard.RecoveryAction(label: "Try Again", style: .secondary, action: .tryAgain),
            ]
        )
    }

    /// Return starts the one enabled primary: YouTube if a URL is present, else a dropped file.
    private func submitPrimaryStemJob() {
        let hasURL = !viewModel.youtubeURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasURL {
            viewModel.startYouTubeSeparation()
        } else if viewModel.canStart {
            viewModel.startSeparation()
        }
    }
}
