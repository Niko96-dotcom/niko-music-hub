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

    public init(
        context: ToolContext,
        viewModel: AudioConverterViewModel
    ) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                intakeSurface
                presetStrip
                actionRow
                batchRows
                Spacer(minLength: 0)
            }
            .hubToolContentPadding()
            .frame(minWidth: 320, idealWidth: 640, maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("WAV Converter", systemImage: "waveform")
                .font(.system(size: 16, weight: .semibold))

            Text(headerStatus)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isConverting {
                ProgressView(value: viewModel.overallProgress)
                    .frame(maxWidth: 320)
                    .tint(Color.accentColor)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    private var intakeSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.card, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: dropTargeted ? 2 : 1
                        )
                }

            VStack(spacing: 8) {
                Text(dropTargeted ? "Release to add supported audio" : "Drop audio files to convert")
                    .font(.system(size: 16, weight: .semibold))

                Text("Add M4A, MP3, WAV, AIFF, or FLAC files. Outputs use the current WAV preset and appear here after verification.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HubIconButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add audio files",
                    help: "Choose files to convert"
                ) {
                    fileImporterVisible = true
                }
            }
            .padding(24)
        }
        .frame(minWidth: 320, idealWidth: 640, maxWidth: HubToolLayout.maxContentWidth, minHeight: 160, alignment: .center)
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
                    .foregroundStyle(.secondary)
                Text(viewModel.presetSummaryText)
                    .font(.system(size: 13))
                    .monospacedDigit()
                Spacer(minLength: 8)
                HubIconButton(
                    systemImage: "slider.horizontal.3",
                    accessibilityLabel: "Edit WAV preset",
                    help: "Sample rate, bit depth, and channels",
                    isSelected: presetEditorVisible
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
        .padding(12)
        .hubGlassCard()
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
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

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HubIconButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add audio files",
                    help: "Choose files to convert to WAV"
                ) {
                    fileImporterVisible = true
                }

                convertButton

                HubIconButton(
                    systemImage: "stop.fill",
                    accessibilityLabel: "Stop after current file",
                    help: "Finish the current file, then stop the batch",
                    isEnabled: viewModel.canRequestStopAfterCurrent
                ) {
                    viewModel.requestStopAfterCurrent()
                }
            }

            ForEach(viewModel.notices, id: \.self) { notice in
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }

    @ViewBuilder
    private var convertButton: some View {
        HubIconButton(
            systemImage: "waveform.badge.plus",
            accessibilityLabel: "Convert to WAV",
            help: "Convert queued files to Cubase-ready WAV",
            prominent: true,
            isEnabled: viewModel.canConvertToWAV
        ) {
            viewModel.startConversion()
        }
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
        HStack(alignment: .top, spacing: 12) {
            statusDot(for: row.state)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.sourceURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let sourceType = row.sourceType {
                        Text(sourceType.rawValue.uppercased())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(row.plannedOutputName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusText(for: row))
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor(for: row.state))
                    .fixedSize(horizontal: false, vertical: true)

                if row.state == .converting {
                    ProgressView(value: row.progress)
                        .frame(maxWidth: 220)
                        .tint(Color.accentColor)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if let converterPathLabel = row.converterPathLabel {
                    Text(converterPathLabel == "FFmpeg" ? "FFmpeg" : "Native")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if row.recoveryActionTitle == "Choose FFmpeg" {
                    Button("Choose FFmpeg") {
                        Task { @MainActor in
                            guard let ffmpegURL = Self.chooseFFmpegExecutableURL() else { return }
                            await viewModel.chooseFFmpegAndRetry(
                                rowID: row.id,
                                ffmpegURL: ffmpegURL
                            )
                        }
                    }
                    .buttonStyle(.bordered)
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
            }
        }
        .padding(12)
        .hubGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.sourceURL.lastPathComponent)
        .accessibilityValue(statusText(for: row))
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
        return StatusDot(state: jobState)
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
            return "This file type is not supported in Phase 3. Add M4A, MP3, WAV, AIFF, or FLAC instead."
        case .skipped:
            return "Skipped"
        }
    }

    private func statusColor(for state: AudioConverterRowState) -> Color {
        switch state {
        case .verified:
            return .green
        case .failed:
            return .red
        case .unsupported:
            return .orange
        case .converting:
            return .accentColor
        case .queued, .skipped:
            return .secondary
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
