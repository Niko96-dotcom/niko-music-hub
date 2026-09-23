import AppCore
import AppKit
import SwiftUI

public struct DownloaderView: View {
    let context: ToolContext

    @ObservedObject private var viewModel: DownloaderViewModel

    public init(
        context: ToolContext,
        viewModel: DownloaderViewModel
    ) {
        self.context = context
        self.viewModel = viewModel
    }

    public var body: some View {
        HubInspectorPage(
            header: { header },
            live: { liveSection },
            primary: { urlCard },
            list: { detailsSection },
            inspector: { inspectorGroups },
            action: { downloadActions }
        )
        .onAppear { viewModel.onAppear() }
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

    @ViewBuilder
    private var liveSection: some View {
        if viewModel.downloadState == .canceled {
            canceledSection
        }
        if viewModel.downloadState == .completed, let message = viewModel.errorMessage {
            handoffWarningSection(message: message)
        }
        if case let .failed(message) = viewModel.downloadState {
            errorSection(message: message)
        }
    }

    private var urlCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
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

            if viewModel.downloadState == .downloading {
                progressSection
            } else {
                Text(DownloaderCopy.trustNotice)
                    .font(HubDesignSystem.Typography.micro())
                    .italic()
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var hasDetails: Bool {
        viewModel.detectedFileName != nil || !viewModel.urlText.isEmpty
    }

    private var detailsSection: some View {
        HubListSection("Details") {
            if hasDetails {
                if let fileName = viewModel.detectedFileName {
                    HubListRow {
                        Text("Title")
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    } trailing: {
                        Text(fileName)
                            .font(HubDesignSystem.Typography.bodySmall())
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if !viewModel.urlText.isEmpty {
                    HubListRow {
                        Text(DownloaderCopy.sourceLabel)
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    } trailing: {
                        Text(viewModel.urlText)
                            .font(HubDesignSystem.Typography.bodySmall())
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HubListRow {
                    Text(DownloaderCopy.formatLabel)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                } trailing: {
                    Text(viewModel.formatSelection.summaryLabel)
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)
                }
                HubListRow {
                    Text(DownloaderCopy.destinationLabel)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                } trailing: {
                    Text(viewModel.outputFolder.path)
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                HubListEmpty("No download yet")
            }
        }
    }

    @ViewBuilder
    private var inspectorGroups: some View {
        HubInspectorGroup("Mode") {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                HubSegmentedChoice(
                    "Playlist mode",
                    selection: $viewModel.playlistMode,
                    // Channel mode is hidden for now (owner decision 2026-09-17).
                    options: DownloadPlaylistMode.allCases.filter { $0 != .channel }.map {
                        .init($0, label: $0.label)
                    }
                )
                // The playlist cap lives in the tooltip so the group never changes height.
                .help(viewModel.playlistMode == .single ? "" : "Playlists download at most \(viewModel.playlistMode.maxEntries ?? 0) items")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HubInspectorGroup("Download as") {
            HubSegmentedChoice(
                DownloaderCopy.mediaKindLabel,
                selection: Binding(
                    get: { viewModel.formatSelection.mediaKind },
                    set: {
                        viewModel.formatSelection.mediaKind = $0
                        viewModel.persistFormatSelection()
                    }
                ),
                options: DownloadMediaKind.allCases.map { .init($0, label: $0.label) }
            )
            .disabled(viewModel.downloadState == .downloading)
        }
        HubInspectorGroup("Format") {
            secondaryFormatMenuChip
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(viewModel.downloadState == .downloading)
        }
    }

    @ViewBuilder
    private var secondaryFormatMenuChip: some View {
        switch viewModel.formatSelection.mediaKind {
        case .audioOnly:
            HubSegmentedChoice(
                DownloaderCopy.audioFormatLabel,
                selection: Binding(
                    get: { viewModel.formatSelection.audioContainer },
                    set: { viewModel.formatSelection.audioContainer = $0; viewModel.persistFormatSelection() }
                ),
                options: [
                    .init(DownloadAudioContainer.best, label: "Best available"),
                    .init(DownloadAudioContainer.wav, label: "WAV"),
                    .init(DownloadAudioContainer.mp3, label: "MP3"),
                    .init(DownloadAudioContainer.m4a, label: "M4A"),
                ],
                columns: 2
            )
        case .videoWithAudio:
            HubSegmentedChoice(
                DownloaderCopy.videoQualityLabel,
                selection: Binding(
                    get: { viewModel.formatSelection.videoQuality },
                    set: { viewModel.formatSelection.videoQuality = $0; viewModel.persistFormatSelection() }
                ),
                options: [
                    .init(DownloadVideoQuality.mp4_360, label: "MP4 360p"),
                    .init(DownloadVideoQuality.mp4_720, label: "MP4 720p"),
                    .init(DownloadVideoQuality.best, label: "Best"),
                ]
            )
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
            .tint(HubDesignSystem.Colors.indicator)

            HStack {
                if viewModel.showsDeterminateProgress {
                    Text("\(Int(viewModel.progress * 100))% complete")
                }
                Spacer()
                TimelineView(.periodic(from: viewModel.downloadStartedAt ?? .now, by: 1)) { context in
                    Text(viewModel.elapsedCaption(at: context.date))
                }
            }
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            if let postProcessingStatus = viewModel.postProcessingStatus {
                Text(postProcessingStatus)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.slowHintVisible {
                Text(DownloadStallMonitor.slowHintMessage)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var downloadActions: some View {
        Group {
            HubLabeledButton(
                icon: "arrow.down.circle",
                label: DownloaderCopy.download,
                style: .primary,
                help: "Download from URL",
                isEnabled: viewModel.downloadState == .readyToDownload || viewModel.downloadState == .canceled,
                expands: true
            ) {
                viewModel.startDownload()
            }

            .background {
                if viewModel.downloadState == .readyToDownload || viewModel.downloadState == .canceled {
                    Button(DownloaderCopy.download) {
                        viewModel.startDownload()
                    }
                    .keyboardShortcut(.defaultAction)
                    .hidden()
                    .accessibilityHidden(true)
                }
            }

            if viewModel.downloadState == .downloading {
                cancelDownloadControl
            }

            if case .failed = viewModel.downloadState {
                HubLabeledButton(
                    icon: "arrow.clockwise",
                    label: "Retry",
                    style: .ghost,
                    expands: true
                ) {
                    viewModel.retryAfterFailure()
                }
            }
        }
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

    /// Esc / ⌘. reach this cancel through the Edit-menu commands
    /// (`HubCancelCommands`), which route by the active tool and running jobs —
    /// no hidden shortcut buttons here, so one owner per key.
    private var cancelDownloadControl: some View {
        HubLabeledButton(
            icon: "xmark",
            label: CancelCopy.cancelDownload,
            style: .ghost,
            help: CancelCopy.cancelDownload,
            expands: true
        ) {
            viewModel.cancelDownload()
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
            case .installHelperTools:
                context.router.requestHelperToolSetup()
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
                    AppErrorCard.RecoveryAction(label: "Install Tools", style: .primary, action: .installHelperTools),
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

/// Inspector menu row: nav-row height, value on the left, chevron on the right.
private struct DownloaderChipLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(title)
                .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: HubDesignSystem.Spacing.navRowHeight)
        .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
    }
}
