import AppCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AudioConverterView: View {
    let context: ToolContext

    @StateObject private var viewModel: AudioConverterViewModel
    @State private var fileImporterVisible = false
    @State private var dropTargeted = false
    @State private var presetEditorVisible = false

    public init(context: ToolContext, viewModel: AudioConverterViewModel) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HubToolPage {
            header
            if viewModel.rows.isEmpty {
                intakeSurface
            } else {
                batchRows
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(icon: "plus", label: "Add files", style: .secondary) {
                        fileImporterVisible = true
                    }
                    if !viewModel.isConverting {
                        HubLabeledButton(icon: "trash", label: "Clear All", style: .ghost) {
                            viewModel.clearAll()
                        }
                    }
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted, perform: handleDrop)
            }
            presetStrip
            actionRow
        }
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
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            ToolHeaderBlock(
                title: "WAV Converter",
                statusText: headerStatus,
                statusColor: HubDesignSystem.Palette.textSecondary
            )

            if viewModel.isConverting {
                Group {
                    if viewModel.overallProgress > 0 {
                        ProgressView(value: viewModel.overallProgress)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
                .tint(HubDesignSystem.Colors.accent)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    private var intakeSurface: some View {
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28, weight: .regular))
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
        .padding(24)
        .frame(maxWidth: HubToolLayout.maxContentWidth, minHeight: 180)
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

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .font(.system(size: 13))

                presetValueSummary

                Spacer(minLength: 8)

                HubLabeledButton(
                    icon: "slider.horizontal.3",
                    label: "Edit Preset",
                    style: .secondary
                ) {
                    presetEditorVisible.toggle()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.presetSummaryText)

            if presetEditorVisible {
                presetEditor
            }
        }
        .padding(10)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    private var presetValueSummary: some View {
        HStack(spacing: 6) {
            Text(AudioConverterViewModel.sampleRateLabel(for: viewModel.currentAudioPreset.sampleRate))
                .font(HubDesignSystem.Typography.mono())
            Text("|")
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            Text("\(viewModel.currentAudioPreset.bitDepth)-bit")
                .font(HubDesignSystem.Typography.mono())
            Text("|")
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            Text(AudioConverterViewModel.channelModeLabel(for: viewModel.currentAudioPreset.channelMode))
                .font(HubDesignSystem.Typography.mono())
        }
    }

    private var presetEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sampleRatePicker
                bitDepthPicker
                channelModePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                sampleRatePicker
                bitDepthPicker
                channelModePicker
            }
        }
    }

    private var sampleRatePicker: some View {
        Picker("Sample rate", selection: sampleRateSelection) {
            Text("44.1 kHz").tag(44100)
            Text("48 kHz").tag(48000)
            Text("88.2 kHz").tag(88200)
            Text("96 kHz").tag(96000)
        }
        .pickerStyle(.menu)
    }

    private var bitDepthPicker: some View {
        Picker("Bit depth", selection: bitDepthSelection) {
            Text("16-bit").tag(16)
            Text("24-bit").tag(24)
            Text("32-bit").tag(32)
        }
        .pickerStyle(.menu)
    }

    private var channelModePicker: some View {
        Picker("Channel handling", selection: channelModeSelection) {
            Text("Preserve mono/stereo").tag(AudioChannelMode.preserveMonoStereo)
            Text("Mono").tag(AudioChannelMode.mono)
            Text("Stereo").tag(AudioChannelMode.stereo)
        }
        .pickerStyle(.menu)
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

    // Unboxed action band — buttons are chrome, not a bounded object, and the
    // dropzone above already owns file intake ("Add Files" was a duplicate).
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "waveform.badge.plus",
                    label: "Convert",
                    style: .primary,
                    isEnabled: viewModel.canConvertToWAV
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
                        style: .secondary,
                        help: AudioConverterCopy.stopAfterThisFileHelp,
                        isEnabled: viewModel.canRequestStopAfterCurrent
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

            ForEach(viewModel.notices, id: \.self) { notice in
                Text(notice)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    private var batchRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.rows) { row in
                batchRow(row)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    @ViewBuilder
    private func batchRow(_ row: AudioConverterRow) -> some View {
        if let verifiedOutputURL = row.verifiedOutputURLForDrag() {
            batchRowContent(row, verifiedOutputURL: verifiedOutputURL)
                .hubDragAffordance()
                .onDrag {
                    NSItemProvider(contentsOf: verifiedOutputURL) ?? NSItemProvider()
                }
        } else {
            batchRowContent(row, verifiedOutputURL: nil)
        }
    }

    private func batchRowContent(
        _ row: AudioConverterRow,
        verifiedOutputURL: URL?
    ) -> some View {
        AudioConverterFlatRow(fillColor: rowFillColor(for: row.state)) {
            HStack(alignment: .top, spacing: 12) {
                statusDot(for: row.state)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.sourceURL.lastPathComponent)
                            .font(HubDesignSystem.Typography.sectionTitle())
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let sourceType = row.sourceType {
                            sourceTypeBadge(sourceType.rawValue.uppercased())
                        }

                        if let converterPathLabel = row.converterPathLabel {
                            sourceTypeBadge(converterPathLabel == "FFmpeg" ? "FFmpeg" : "Native")
                        }
                    }

                    Text(row.plannedOutputName)
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(statusText(for: row))
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(statusColor(for: row.state))
                        .fixedSize(horizontal: false, vertical: true)

                    if row.state == .converting {
                        ProgressView(value: row.progress)
                            .frame(maxWidth: 220)
                            .tint(HubDesignSystem.Colors.accent)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
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

                    if verifiedOutputURL != nil {
                        HubIconButton(
                            systemImage: "folder",
                            accessibilityLabel: "Reveal in Finder",
                            help: "Show converted WAV in Finder"
                        ) {
                            if let verifiedOutputURL {
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
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.sourceURL.lastPathComponent)
        .accessibilityValue(statusText(for: row))
    }

    private func rowFillColor(for state: AudioConverterRowState) -> Color? {
        switch state {
        case .verified:
            return HubDesignSystem.Palette.accentFill
        case .failed:
            return HubDesignSystem.Palette.danger.opacity(0.12)
        case .unsupported:
            return HubDesignSystem.Palette.warning.opacity(0.12)
        case .queued, .converting, .skipped:
            return nil
        }
    }

    private func sourceTypeBadge(_ label: String) -> some View {
        Text(label)
            .font(HubDesignSystem.Typography.micro())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                    .fill(HubDesignSystem.Palette.accentFill)
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
            return "Ready for WAV conversion"
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
            return "Ready for WAV conversion"
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

/// Flat batch row wrapper (IA-08): transparent at rest, `white 5%` on hover, no
/// per-row border/shadow. An optional semantic `fillColor` washes the row at rest
/// (e.g. verified/failed/unsupported) without introducing a bounded card look.
private struct AudioConverterFlatRow<Content: View>: View {
    let fillColor: Color?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                    .fill(fillColor ?? (isHovered ? Color.white.opacity(0.05) : Color.clear))
            }
            .onHover { isHovered = $0 }
    }
}
