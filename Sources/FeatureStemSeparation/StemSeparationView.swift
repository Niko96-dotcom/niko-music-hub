import AppCore
import SwiftUI
import UniformTypeIdentifiers

public struct StemSeparationView: View {
    @StateObject private var viewModel: StemSeparationViewModel

    public init(viewModel: StemSeparationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        HubToolPage {
            header
            fileWell
            youtubeWell
            controls
            progressSection
            errorBanner
            resultsList
        }
        .onAppear { viewModel.onAppear() }
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "Stem Separation",
            systemImage: "slider.horizontal.below.rectangle",
            statusText: viewModel.statusMessage,
            statusColor: viewModel.errorMessage == nil
                ? HubDesignSystem.Palette.textSecondary
                : HubDesignSystem.Colors.warning
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileWell: some View {
        VStack(spacing: 12) {
            if let fileURL = viewModel.droppedFileURL {
                VStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    Text(fileURL.lastPathComponent)
                        .font(HubDesignSystem.Typography.sectionTitle())
                    Text(fileURL.path)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "arrow.down.document")
                    .font(.system(size: 32))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Text("Drop an audio file here")
                    .font(HubDesignSystem.Typography.sectionTitle())
                Text("WAV, AIFF, MP3, M4A, FLAC")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            HStack(spacing: 12) {
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
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .hubCard(cornerRadius: HubDesignSystem.Radius.card, interactive: true)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) else { continue }
                    guard let data = item as? Data else { continue }
                    guard let string = String(data: data, encoding: .utf8) else { continue }
                    guard let url = URL(string: string) else { continue }
                    urls.append(url)
                }
                await MainActor.run {
                    _ = viewModel.handleDrop(urls: urls)
                }
            }
            return true
        }
    }

    private var youtubeWell: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Paste YouTube URL…", text: $viewModel.youtubeURLText)
                .textFieldStyle(.plain)
                .font(HubDesignSystem.Typography.body())
                .disabled(viewModel.isRunning)

            HubLabeledButton(
                icon: "arrow.down.circle",
                label: "Download & Separate",
                style: .primary,
                isEnabled: viewModel.canStartYouTube
            ) {
                viewModel.startYouTubeSeparation()
            }

            if !viewModel.youtubeURLText.isEmpty {
                Button {
                    viewModel.clearYouTubeURL()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear YouTube URL")
                .disabled(viewModel.isRunning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
        .opacity(viewModel.isRunning ? 0.6 : 1)
        .disabled(viewModel.isRunning)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubChoiceChips(
                "Preset",
                selection: $viewModel.selectedPreset,
                choices: viewModel.supportedPresets.map {
                    .init($0, label: $0.displayName, help: $0.shortDescription)
                }
            )

            HStack {
                Text("Output: \(viewModel.outputFolderURL.path)")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()

                HubLabeledButton(
                    icon: "folder",
                    label: "Choose Output Folder",
                    style: .secondary,
                    isEnabled: !viewModel.isRunning
                ) {
                    viewModel.pickOutputFolder()
                }
            }

            HStack(spacing: 12) {
                HubLabeledButton(
                    icon: "waveform.path.ecg",
                    label: "Start Separation",
                    style: .primary,
                    isEnabled: viewModel.canStart
                ) {
                    viewModel.startSeparation()
                }

                HubLabeledButton(
                    icon: "xmark",
                    label: "Cancel",
                    style: .secondary,
                    isEnabled: viewModel.canCancel
                ) {
                    viewModel.cancelSeparation()
                }
            }
        }
        .padding(12)
        .hubCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    @ViewBuilder
    private var progressSection: some View {
        if viewModel.isRunning {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                ProgressView(value: viewModel.progress)
                    .tint(HubDesignSystem.Colors.accent)
                Text("\(Int(viewModel.progress * 100))% complete")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .selected)
        }
    }

    private var errorBanner: some View {
        Group {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .error)
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if !viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HubSectionHeader("Separated Stems", count: viewModel.results.count)

                ForEach(viewModel.results) { item in
                    resultRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultRow(_ item: OutputInboxItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileURL.lastPathComponent)
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let role = item.metadata["displayName"] {
                    Text(role)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HubLabeledButton(
                icon: "folder",
                label: "Reveal",
                style: .ghost
            ) {
                viewModel.reveal(item: item)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .onDrag {
            guard let url = viewModel.dragURL(for: item) else {
                return NSItemProvider()
            }
            return NSItemProvider(object: url as NSURL)
        }
    }
}
