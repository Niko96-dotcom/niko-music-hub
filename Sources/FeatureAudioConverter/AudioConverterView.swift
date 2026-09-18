import AppCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AudioConverterView: View {
    let context: ToolContext

    /// Owned by the feature session (`viewModel(for:)`), not by this view.
    @ObservedObject private var viewModel: AudioConverterViewModel
    @State private var fileImporterVisible = false
    @State private var dropTargeted = false
    @State private var presetEditorVisible = false

    public init(context: ToolContext, viewModel: AudioConverterViewModel) {
        self.context = context
        self.viewModel = viewModel
    }

    public var body: some View {
        HubInspectorPage(
            header: { header },
            live: { liveSection },
            primary: { intakeSurface },
            list: { queueSection },
            inspector: { inspectorGroups },
            action: { convertActions }
        )
        .fileImporter(
            isPresented: $fileImporterVisible,
            allowedContentTypes: allowedAudioTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                viewModel.addFileURLs(urls)
            }
        }
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "WAV Converter",
            statusText: headerStatus,
            statusColor: HubDesignSystem.Palette.textSecondary
        )
    }

    @ViewBuilder
    private var liveSection: some View {
        if viewModel.isConverting {
            convertingProgressRow
        }
        if showsFFmpegNotice {
            ffmpegNoticeCard
        }
        if !viewModel.notices.isEmpty {
            noticesSection
        }
    }

    private var convertingProgressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if viewModel.overallProgress > 0 {
                    ProgressView(value: viewModel.overallProgress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 320)
            .tint(HubDesignSystem.Colors.indicator)
            Text(viewModel.statusText)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
    }

    private var showsFFmpegNotice: Bool {
        viewModel.rows.contains(
            where: { $0.recoveryActionTitle == AudioConverterCopy.chooseFFmpeg }
        )
    }

    private var ffmpegNoticeCard: some View {
        Text(AudioConverterCopy.missingFFmpeg)
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HubDesignSystem.Spacing.section)
            .hubCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var intakeSurface: some View {
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "doc.badge.plus")
                .font(HubDesignSystem.Typography.display())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            Text(dropTargeted ? "Release to add supported audio" : "Drop audio files to convert")
                .font(HubDesignSystem.Typography.sectionTitle())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("M4A, MP3, WAV, AIFF, or FLAC accepted")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HubLabeledButton(
                icon: "plus",
                label: "Choose Files",
                style: .secondary
            ) {
                fileImporterVisible = true
            }
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hubCard(
            cornerRadius: HubDesignSystem.Radius.card,
            state: dropTargeted ? .selected : .normal,
            interactive: true
        )
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $dropTargeted,
            perform: handleDrop
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop audio files to convert")
    }

    private var queueSection: some View {
        HubListSection("Queue", count: viewModel.rows.count, trailing: {
            HubLabeledButton(icon: "plus", label: "Add files", style: .ghost) {
                fileImporterVisible = true
            }
            if !viewModel.rows.isEmpty, !viewModel.isConverting {
                HubLabeledButton(icon: "trash", label: "Clear All", style: .ghost) {
                    viewModel.clearAll()
                }
            }
        }) {
            if viewModel.rows.isEmpty {
                HubListEmpty("No files queued")
            } else {
                ForEach(viewModel.rows) { row in
                    queueRow(row)
                }
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted, perform: handleDrop)
    }

    private var noticesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.notices, id: \.self) { notice in
                Text(notice)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    @ViewBuilder
    private func queueRow(_ row: AudioConverterRow) -> some View {
        if let verifiedOutputURL = row.verifiedOutputURLForDrag() {
            queueRowContent(row)
                .hubDragAffordance()
                .onDrag {
                    NSItemProvider(contentsOf: verifiedOutputURL) ?? NSItemProvider()
                }
        } else {
            queueRowContent(row)
        }
    }

    private func queueRowContent(_ row: AudioConverterRow) -> some View {
        HubListRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.sourceURL.lastPathComponent)
                    .font(HubDesignSystem.Typography.body())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusText(for: row))
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(statusColor(for: row.state))
                    .fixedSize(horizontal: false, vertical: true)

                if row.state == .converting {
                    ProgressView(value: row.progress)
                        .frame(maxWidth: 220)
                        .tint(HubDesignSystem.Colors.indicator)
                }
            }
        } trailing: {
            statusDot(for: row.state)

            if row.recoveryActionTitle == "Choose FFmpeg" {
                HubLabeledButton(
                    icon: "hammer",
                    label: "Choose FFmpeg",
                    style: .ghost
                ) {
                    Task { @MainActor in
                        guard let ffmpegURL = Self.chooseFFmpegExecutableURL() else { return }
                        await viewModel.chooseFFmpegAndRetry(
                            rowID: row.id,
                            ffmpegURL: ffmpegURL
                        )
                    }
                }
            }

            if row.verifiedOutputURLForDrag() != nil {
                HubIconButton(
                    systemImage: "folder",
                    accessibilityLabel: "Reveal in Finder",
                    help: "Show converted WAV in Finder"
                ) {
                    if let verifiedOutputURL = row.verifiedOutputURLForDrag() {
                        context.fileActions.revealInFinder(verifiedOutputURL)
                    }
                }
            }

            HubIconButton(
                systemImage: "minus.circle",
                accessibilityLabel: "Remove file",
                help: "Remove this file from the batch",
                role: .destructive,
                isEnabled: !viewModel.isConverting || row.state != .converting
            ) { viewModel.removeRow(id: row.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.sourceURL.lastPathComponent)
        .accessibilityValue(statusText(for: row))
    }

    @ViewBuilder
    private var inspectorGroups: some View {
        HubInspectorGroup("Preset") {
            Button {
                presetEditorVisible.toggle()
            } label: {
                HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                    presetValueSummary
                    Spacer(minLength: 0)
                    Image(systemName: presetEditorVisible ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
                .hubInspectorRow()
                .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable()
            .focusEffectDisabled()
            .help(presetEditorVisible ? "Hide preset editor" : "Edit Preset")
            .accessibilityLabel("Edit Preset")
            .accessibilityValue(viewModel.presetSummaryText)
        }
        if presetEditorVisible {
            HubInspectorGroup("Sample rate") {
                HubSegmentedChoice("Sample rate", selection: sampleRateSelection, options: [
                    .init(44100, label: "44.1 kHz"),
                    .init(48000, label: "48 kHz"),
                    .init(88200, label: "88.2 kHz"),
                    .init(96000, label: "96 kHz"),
                ], columns: 2)
            }
            HubInspectorGroup("Bit depth") {
                HubSegmentedChoice("Bit depth", selection: bitDepthSelection, options: [
                    .init(16, label: "16-bit"),
                    .init(24, label: "24-bit"),
                    .init(32, label: "32-bit"),
                ])
            }
            HubInspectorGroup("Channel handling") {
                HubSegmentedChoice("Channel handling", selection: channelModeSelection, options: [
                    .init(AudioChannelMode.preserveMonoStereo, label: "Preserve"),
                    .init(AudioChannelMode.mono, label: "Mono"),
                    .init(AudioChannelMode.stereo, label: "Stereo"),
                ])
            }
        }
    }

    private var presetValueSummary: some View {
        Text("\(AudioConverterViewModel.sampleRateLabel(for: viewModel.currentAudioPreset.sampleRate)) · \(viewModel.currentAudioPreset.bitDepth)-bit · \(channelShortLabel)")
            .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var channelShortLabel: String {
        switch viewModel.currentAudioPreset.channelMode {
        case .preserveMonoStereo: "Preserve"
        case .mono: "Mono"
        case .stereo: "Stereo"
        }
    }

    private var sampleRateSelection: Binding<Int> {
        Binding(
            get: { viewModel.currentAudioPreset.sampleRate },
            set: { sampleRate in
                viewModel.updateWAVPreset(sampleRate: sampleRate, bitDepth: viewModel.currentAudioPreset.bitDepth, channelMode: viewModel.currentAudioPreset.channelMode)
            }
        )
    }

    private var bitDepthSelection: Binding<Int> {
        Binding(
            get: { viewModel.currentAudioPreset.bitDepth },
            set: { bitDepth in
                viewModel.updateWAVPreset(sampleRate: viewModel.currentAudioPreset.sampleRate, bitDepth: bitDepth, channelMode: viewModel.currentAudioPreset.channelMode)
            }
        )
    }

    private var channelModeSelection: Binding<AudioChannelMode> {
        Binding(
            get: { viewModel.currentAudioPreset.channelMode },
            set: { channelMode in
                viewModel.updateWAVPreset(sampleRate: viewModel.currentAudioPreset.sampleRate, bitDepth: viewModel.currentAudioPreset.bitDepth, channelMode: channelMode)
            }
        )
    }

    private var convertActions: some View {
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            HubLabeledButton(
                icon: "waveform.badge.plus",
                label: "Convert",
                style: .primary,
                isEnabled: viewModel.canConvertToWAV,
                expands: true
            ) {
                viewModel.startConversion()
            }

            if viewModel.canConvertToWAV {
                Button("Convert") {
                    viewModel.startConversion()
                }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
            }

            if viewModel.isConverting {
                HubLabeledButton(
                    icon: "stop.fill",
                    label: AudioConverterCopy.stopAfterThisFile,
                    style: .ghost,
                    help: AudioConverterCopy.stopAfterThisFileHelp,
                    isEnabled: viewModel.canRequestStopAfterCurrent,
                    expands: true
                ) {
                    viewModel.requestStopAfterCurrent()
                }
                Button(AudioConverterCopy.stopAfterThisFile) {
                    viewModel.requestStopAfterCurrent()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!viewModel.canRequestStopAfterCurrent)
                .hidden()
                .accessibilityHidden(true)
            }
        }
    }

    private func statusDot(for state: AudioConverterRowState) -> some View {
        let jobState: JobState
        switch state {
        case .queued:
            jobState = .queued
        case .converting:
            jobState = .running
        case .verified:
            jobState = .completed
        case .failed:
            jobState = .failed
        case .unsupported:
            jobState = .canceled
        case .skipped:
            jobState = .canceled
        }
        // Row already exposes statusText via the combined accessibility label/value,
        // so hide the symbol from VoiceOver to avoid double-speaking (NMH-079).
        return StatusDot(state: jobState).accessibilityHidden(true)
    }

    private func statusText(for row: AudioConverterRow) -> String {
        switch row.state {
        case .queued:
            return AudioConverterCopy.ready
        case .converting:
            return "Converting to Cubase-ready WAV"
        case .verified:
            return "Verified WAV ready"
        case .failed:
            return row.statusText
        case .unsupported:
            return row.statusText
        case .skipped:
            return "Skipped"
        }
    }

    private func statusColor(for state: AudioConverterRowState) -> Color {
        switch state {
        case .verified:
            return HubDesignSystem.Colors.success
        case .failed:
            return HubDesignSystem.Colors.danger
        case .unsupported:
            return HubDesignSystem.Colors.warning
        case .converting:
            return HubDesignSystem.Colors.accent
        case .queued, .skipped:
            return HubDesignSystem.Palette.textSecondary
        }
    }

    private var headerStatus: String {
        if viewModel.rows.isEmpty {
            return ""
        }
        if viewModel.isConverting {
            return "Converting to Cubase-ready WAV"
        }
        return viewModel.statusText
    }

    private var allowedAudioTypes: [UTType] {
        AudioFileIntakeScanner.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else { return false }

        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = Self.fileURL(from: item) else { return }
                Task { @MainActor in
                    viewModel.addFileURLs([url])
                }
            }
        }

        return true
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }

    @MainActor
    private static func chooseFFmpegExecutableURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose FFmpeg"
        panel.message = "Select the ffmpeg executable."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
