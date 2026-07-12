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
            intakeWell
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

    /// One intake object: drop/choose a local file, or paste a YouTube URL —
    /// two routes into the same separation, so they share one card.
    private var intakeWell: some View {
        VStack(spacing: 12) {
            fileIntakeContent

            Divider().opacity(0.35)

            youtubeRow
        }
        .frame(maxWidth: .infinity)
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

    private var fileIntakeContent: some View {
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
        .frame(maxWidth: .infinity, minHeight: 108)
    }

    private var youtubeRow: some View {
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
                Text("Output: \(viewModel.outputFolderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
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

                if viewModel.canCancel {
                    HubLabeledButton(
                        icon: "xmark",
                        label: "Cancel",
                        style: .secondary
                    ) {
                        viewModel.cancelSeparation()
                    }
                }
            }
        }
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

    private var resultsList: some View {
        ToolOutputShelf(
            title: "Separated Stems",
            items: viewModel.results,
            subtitle: { $0.metadata["displayName"] },
            onReveal: { viewModel.reveal(item: $0) }
        )
    }
}
