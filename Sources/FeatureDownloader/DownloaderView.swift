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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        parts.append(formatter.localizedString(for: item.createdAt, relativeTo: Date()))
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        ToolHeaderBlock(
            title: DownloaderCopy.toolLabel,
            systemImage: "arrow.down.circle",
            statusText: headerStatus,
            statusColor: HubDesignSystem.Palette.textSecondary
        )
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
        case .completed:
            return DownloaderCopy.downloadComplete
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

            HubLabeledButton(
                icon: "arrow.down.circle",
                label: DownloaderCopy.download,
                style: .primary,
                help: "Download from URL",
                isEnabled: viewModel.downloadState == .readyToDownload
            ) {
                viewModel.startDownload()
            }

            if !viewModel.urlText.isEmpty {
                Button {
                    viewModel.clearInput()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help(DownloaderCopy.clear)
                .disabled(viewModel.downloadState == .downloading)
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
        HStack(spacing: 8) {
            ForEach(DownloadPlaylistMode.allCases) { mode in
                Button {
                    viewModel.playlistMode = mode
                } label: {
                    Text(mode.label)
                        .font(HubDesignSystem.Typography.caption())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(
                                    viewModel.playlistMode == mode
                                        ? HubDesignSystem.Palette.accentFill
                                        : Color.white.opacity(0.05)
                                )
                        }
                }
                .buttonStyle(.plain)
            }
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

            DownloaderTextChip(
                title: "Audio only",
                isSelected: viewModel.formatSelection.mediaKind == .audioOnly
            ) {
                viewModel.formatSelection.mediaKind = .audioOnly
                viewModel.persistFormatSelection()
            }

            DownloaderTextChip(
                title: "Video + audio",
                isSelected: viewModel.formatSelection.mediaKind == .videoWithAudio
            ) {
                viewModel.formatSelection.mediaKind = .videoWithAudio
                viewModel.persistFormatSelection()
            }

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
            ProgressView(value: viewModel.progress)
                .tint(HubDesignSystem.Colors.accent)

            Text("\(Int(viewModel.progress * 100))% complete")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
        .padding(12)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .selected)
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
            if action == .tryAgain {
                viewModel.retryAfterFailure()
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

    private static func errorCard(for message: String) -> AppErrorCard {
        let lower = message.lowercased()
        if lower.contains("yt-dlp is required") || lower.contains("yt-dlp path") || lower.contains("outdated") {
            return AppErrorCard(
                category: .helperTool,
                label: "yt-dlp Not Found",
                icon: "tool.badge.xmark",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open Terminal", style: .primary, action: .openTerminal),
                    AppErrorCard.RecoveryAction(label: "Retry", style: .secondary, action: .tryAgain)
                ]
            )
        }
        if lower.contains("error:") || lower.contains("unsupported") || lower.contains("video unavailable") {
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

private struct DownloaderTextChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(isSelected ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: HubDesignSystem.Size.chipHeight)
                .background {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                        .fill(isSelected ? HubDesignSystem.Palette.accentFill : (isHovered ? Color.white.opacity(0.05) : Color.clear))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DownloaderChipLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(HubDesignSystem.Typography.caption())
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
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
