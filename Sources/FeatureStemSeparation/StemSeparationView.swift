import AppCore
import SwiftUI
import UniformTypeIdentifiers

public struct StemSeparationView: View {
    @StateObject private var viewModel: StemSeparationViewModel
    @State private var isTargeted = false

    public init(viewModel: StemSeparationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        if viewModel.isRunning {
            progressRow
        }
        if viewModel.helperNeedsSetup {
            StandardErrorCard(card: Self.helperMissingCard()) { action in
                switch action {
                case .chooseToolPath:
                    viewModel.chooseHelperPath()
                case .openHubSettingsHelpers:
                    HubSettingsHelpersAction.openSettingsHelpers()
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
            .tint(HubDesignSystem.Colors.accent)
            Text(viewModel.statusMessage)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    /// Intake card: the drop zone on top, the YouTube route below the divider.
    /// Compact spacing and caption sizes so both routes fit the 168pt slot.
    private var intakeCard: some View {
        VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            fileIntakeContent
            Divider()
            youtubeRow
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
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            if let fileURL = viewModel.droppedFileURL {
                Image(systemName: "waveform")
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(HubDesignSystem.Typography.body())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileURL.path)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Image(systemName: "arrow.down.document")
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop an audio file here")
                        .font(HubDesignSystem.Typography.body())
                    Text("WAV, AIFF, MP3, M4A, FLAC")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HubLabeledButton(
                icon: "folder",
                label: "Choose File",
                style: .secondary,
                isEnabled: !viewModel.isRunning
            ) {
                viewModel.selectFile()
            }
            if viewModel.droppedFileURL != nil {
                HubLabeledButton(
                    icon: "xmark",
                    label: "Clear",
                    style: .ghost,
                    isEnabled: !viewModel.isRunning
                ) {
                    viewModel.clearSelection()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop an audio file or choose a file to separate")
        .accessibilityHint("Accepts WAV, AIFF, MP3, M4A, or FLAC.")
    }

    private var youtubeRow: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "play.rectangle")
                .font(HubDesignSystem.Typography.body().weight(.medium))
                .foregroundStyle(.tertiary)

            HubQuietTextField("Paste YouTube URL…", text: $viewModel.youtubeURLText)
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
        .opacity(viewModel.isRunning ? 0.6 : 1)
        .disabled(viewModel.isRunning)
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
                    .background(
                        RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                            .fill(HubDesignSystem.Palette.surfaceRaised)
                    )
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
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            HubLabeledButton(
                icon: "waveform.path.ecg",
                label: "Start Separation",
                style: .primary,
                isEnabled: viewModel.canStart,
                expands: true
            ) {
                viewModel.startSeparation()
            }

            if viewModel.canStart || viewModel.canStartYouTube {
                Button(viewModel.canStartYouTube ? "Download & Separate" : "Start Separation") {
                    submitPrimaryStemJob()
                }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
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
                Button("Cancel") {
                    viewModel.cancelSeparation()
                }
                .keyboardShortcut(.cancelAction)
                .hidden()
                .accessibilityHidden(true)
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
                AppErrorCard.RecoveryAction(label: "Choose Path", style: .primary, action: .chooseToolPath),
                AppErrorCard.RecoveryAction(label: "Open Settings", style: .secondary, action: .openHubSettingsHelpers),
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
