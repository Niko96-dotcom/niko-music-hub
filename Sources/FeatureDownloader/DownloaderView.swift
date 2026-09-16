import AppCore
import AppKit
import SwiftUI

public struct DownloaderView: View {
    let context: ToolContext

    @StateObject private var viewModel: DownloaderViewModel

    public init(
        context: ToolContext,
        viewModel: DownloaderViewModel
    ) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HubToolPage {
            header
            urlInputRow
            playlistModeStrip
            formatChipStrip
            if viewModel.downloadState == .readyToDownload || viewModel.downloadState == .downloading {
                trustInfoCard
            }
            if viewModel.downloadState == .downloading {
                progressSection
                logArea
            }
            if viewModel.downloadState == .canceled {
                canceledSection
            }
            if viewModel.downloadState == .completed, let message = viewModel.errorMessage {
                handoffWarningSection(message: message)
            }
            if case let .failed(message) = viewModel.downloadState {
                errorSection(message: message)
            }
            downloadsSection
        }
        .onAppear { viewModel.onAppear() }
    }

    /// Latest finished downloads, each a draggable card — drop one straight into a DAW.
    private var downloadsSection: some View {
        ToolOutputShelf(
            title: "Downloads",
            items: viewModel.recentDownloads,
            subtitle: downloadSubtitle,
            onReveal: { item in
                context.fileActions.revealInFinder(item.fileURL)
            }
        )
    }

    private func downloadSubtitle(for item: OutputInboxItem) -> String? {
        var parts: [String] = []
        if let source = item.metadata["dlSourceURL"],
           let host = URL(string: source)?.host {
            parts.append(host)
        }
        parts.append(HubRelativeTime.string(for: item.createdAt))
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        ToolHeaderBlock(
            title: DownloaderCopy.toolLabel,
            statusText: headerStatus,
            statusColor: headerStatusColor
        )
    }

    /// NMH-097: failed headers use danger; idle/running/canceled stay secondary.
    private var headerStatusColor: Color {
        if case .failed = viewModel.downloadState {
            return HubDesignSystem.Colors.danger
        }
        return HubDesignSystem.Palette.textSecondary
    }

    private var headerStatus: String {
        switch viewModel.downloadState {
        case .idle:
            return DownloaderCopy.idleSubtitle
        case .checkingURL:
            return DownloaderCopy.checkingURL
        case .readyToDownload:
            return viewModel.statusMessage ?? DownloaderCopy.readyToDownload
        case .downloading:
            return viewModel.statusMessage ?? DownloaderCopy.downloading
        case .canceled:
            return DownloaderCopy.downloadCanceled
        case .completed:
            // NMH-141: prefer an explicit status message so the
            // already-exists skip reads as status, not a generic failure.
            // Normal completions set "Downloaded", identical to the fallback.
            return viewModel.statusMessage ?? DownloaderCopy.downloadComplete
        case let .failed(message):
            return message
        }
    }

    private var urlInputRow: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            TextField(DownloaderCopy.urlPlaceholder, text: $viewModel.urlText)
                .textFieldStyle(.plain)
                .onChange(of: viewModel.urlText) { _, _ in
                    viewModel.urlTextDidChange()
                }
                .onSubmit {
                    viewModel.submitIfReady()
                }

            HubLabeledButton(
                icon: "arrow.down.circle",
                label: DownloaderCopy.download,
                style: .primary,
                help: "Download from URL",
                isEnabled: viewModel.downloadState == .readyToDownload || viewModel.downloadState == .canceled
            ) {
                viewModel.startDownload()
            }

            if viewModel.downloadState == .readyToDownload || viewModel.downloadState == .canceled {
                Button(DownloaderCopy.download) {
                    viewModel.startDownload()
                }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
            }

            if !viewModel.urlText.isEmpty {
                HubIconButton(
                    systemImage: "xmark.circle.fill",
                    accessibilityLabel: DownloaderCopy.clear,
                    help: DownloaderCopy.clear,
                    isEnabled: viewModel.downloadState != .downloading
                ) {
                    viewModel.clearInput()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
        .opacity(viewModel.downloadState == .downloading ? 0.62 : 1)
        .disabled(viewModel.downloadState == .downloading)
    }

    private var playlistModeStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            HubChoiceChips(
                "Playlist mode",
                selection: $viewModel.playlistMode,
                choices: DownloadPlaylistMode.allCases.map {
                    .init($0, label: $0.label)
                }
            )
            if viewModel.playlistMode != .single {
                Text("Max \(viewModel.playlistMode.maxEntries ?? 0) items")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var formatChipStrip: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.cardGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
                    formatStripContent
                }
                VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    formatStripContent
                }
            }

            if let fileName = viewModel.detectedFileName {
                Text(fileName)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .disabled(viewModel.downloadState == .downloading)
    }

    private var formatStripContent: some View {
        Group {
            Text("Download as:")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            HubChoiceChips(
                DownloaderCopy.mediaKindLabel,
                selection: Binding(
                    get: { viewModel.formatSelection.mediaKind },
                    set: {
                        viewModel.formatSelection.mediaKind = $0
                        viewModel.persistFormatSelection()
                    }
                ),
                choices: DownloadMediaKind.allCases.map { .init($0, label: $0.label) }
            )

            Text("Format:")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .padding(.leading, 4)

            secondaryFormatMenuChip
        }
    }

    @ViewBuilder
    private var secondaryFormatMenuChip: some View {
        switch viewModel.formatSelection.mediaKind {
        case .audioOnly:
            Menu {
                Picker(DownloaderCopy.audioFormatLabel, selection: $viewModel.formatSelection.audioContainer) {
                    Text("Best available").tag(DownloadAudioContainer.best)
                    Text("WAV").tag(DownloadAudioContainer.wav)
                    Text("MP3").tag(DownloadAudioContainer.mp3)
                    Text("M4A").tag(DownloadAudioContainer.m4a)
                }
                .onChange(of: viewModel.formatSelection.audioContainer) { _, _ in
                    viewModel.persistFormatSelection()
                }
            } label: {
                DownloaderChipLabel(title: audioFormatChipTitle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        case .videoWithAudio:
            Menu {
                Picker(DownloaderCopy.videoQualityLabel, selection: $viewModel.formatSelection.videoQuality) {
                    Text("MP4 (360p)").tag(DownloadVideoQuality.mp4_360)
                    Text("MP4 (720p)").tag(DownloadVideoQuality.mp4_720)
                    Text("Best quality").tag(DownloadVideoQuality.best)
                }
                .onChange(of: viewModel.formatSelection.videoQuality) { _, _ in
                    viewModel.persistFormatSelection()
                }
            } label: {
                DownloaderChipLabel(title: videoFormatChipTitle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var audioFormatChipTitle: String {
        switch viewModel.formatSelection.audioContainer {
        case .best: return "Best"
        case .wav: return "WAV"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        }
    }

    private var videoFormatChipTitle: String {
        switch viewModel.formatSelection.videoQuality {
        case .mp4_360: return "MP4 360p"
        case .mp4_720: return "MP4 720p"
        case .best: return "Best"
        }
    }

    private var trustInfoCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.cardGap) {
            Label("Download details", systemImage: "shield.lefthalf.filled")
                .font(HubDesignSystem.Typography.sectionTitle())
                .foregroundStyle(HubDesignSystem.Colors.accent)

            LabeledContent(DownloaderCopy.sourceLabel) {
                Text(viewModel.urlText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            LabeledContent(DownloaderCopy.formatLabel) {
                Text(viewModel.formatSelection.summaryLabel)
                    .lineLimit(1)
            }

            LabeledContent(DownloaderCopy.destinationLabel) {
                Text(viewModel.outputFolder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(DownloaderCopy.trustNotice)
                .font(HubDesignSystem.Typography.micro())
                .italic()
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Group {
                if viewModel.showsDeterminateProgress {
                    ProgressView(value: viewModel.progress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(HubDesignSystem.Colors.accent)

            if viewModel.showsDeterminateProgress {
                Text("\(Int(viewModel.progress * 100))% complete")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }

            TimelineView(.periodic(from: viewModel.downloadStartedAt ?? .now, by: 1)) { context in
                Text(viewModel.elapsedCaption(at: context.date))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }

            if viewModel.slowHintVisible {
                Text(DownloadStallMonitor.slowHintMessage)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            cancelDownloadControl
        }
        .padding(12)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .selected)
    }

    private var canceledSection: some View {
        Text(viewModel.statusMessage ?? DownloaderCopy.downloadCanceledDetail)
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    private var cancelDownloadControl: some View {
        HStack {
            HubLabeledButton(
                icon: "xmark",
                label: CancelCopy.cancelDownload,
                style: .secondary,
                help: CancelCopy.cancelDownload
            ) {
                viewModel.cancelDownload()
            }
            Button(CancelCopy.cancelDownload) {
                viewModel.cancelDownload()
            }
            .keyboardShortcut(.cancelAction)
            .hidden()
            .accessibilityHidden(true)
            Button(CancelCopy.cancelDownload) {
                viewModel.cancelDownload()
            }
            .keyboardShortcut(".", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
        }
    }

    private var logArea: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text("Log")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.logEntries, id: \.self) { entry in
                    Text(entry)
                        .font(HubDesignSystem.Typography.mono(size: 10))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row)
        }
    }

    private func errorSection(message: String) -> some View {
        let card = Self.errorCard(for: message)
        return StandardErrorCard(card: card) { action in
            switch action {
            case .tryAgain:
                if card.category == .helperTool {
                    viewModel.retryHelperSetup()
                } else {
                    viewModel.retryAfterFailure()
                }
            case .openHubSettingsHelpers:
                HubSettingsHelpersAction.openSettingsHelpers()
            case .chooseToolPath:
                viewModel.chooseYtDlpPath()
            default:
                break
            }
        }
    }

    private func handoffWarningSection(message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Colors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
    }

    static func errorCard(for message: String) -> AppErrorCard {
        let lower = message.lowercased()
        if lower.contains("yt-dlp is required") || lower.contains("yt-dlp path") || lower.contains("outdated") {
            return AppErrorCard(
                category: .helperTool,
                label: "yt-dlp Not Found",
                icon: "tool.badge.xmark",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open Settings", style: .primary, action: .openHubSettingsHelpers),
                    AppErrorCard.RecoveryAction(label: "Choose Path", style: .secondary, action: .chooseToolPath),
                    AppErrorCard.RecoveryAction(label: "Try Again", style: .secondary, action: .tryAgain)
                ]
            )
        }
        if lower.contains("http error 403") || lower.contains("forbidden") {
            return AppErrorCard(
                category: .conversionFile,
                label: "Download Temporarily Blocked",
                icon: "arrow.trianglehead.2.clockwise.rotate.90.circle",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        }
        if lower.contains("unsupported") || lower.contains("video unavailable") {
            return AppErrorCard(
                category: .inputURL,
                label: "URL Not Supported",
                icon: "link.badge.plus",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        }
        return AppErrorCard(
            category: .conversionFile,
            label: "Download Failed",
            icon: "arrow.down.circle.badge.xmark",
            body: message,
            recoveryActions: [
                AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
            ]
        )
    }
}

// MARK: - Chip helpers

private struct DownloaderChipLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(HubDesignSystem.Typography.caption())
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        .padding(.horizontal, 10)
        .frame(height: HubDesignSystem.Size.chipHeight)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                .fill(HubDesignSystem.Palette.accentFill)
        }
    }
}
