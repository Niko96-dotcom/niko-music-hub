import AppCore
import SwiftUI
import UniformTypeIdentifiers

public struct StemSeparationView: View {
    @StateObject private var viewModel: StemSeparationViewModel

    public init(viewModel: StemSeparationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 16) {
            fileWell
            youtubeWell
            controls
            progressSection
            errorBanner
            resultsList
            Spacer()
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { viewModel.onAppear() }
    }

    private var fileWell: some View {
        VStack(spacing: 12) {
            if let fileURL = viewModel.droppedFileURL {
                VStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "arrow.down.document")
                    .font(.system(size: 32))
                Text("Drop an audio file here")
                    .font(.headline)
                Text("WAV, AIFF, MP3, M4A, FLAC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Choose File...") {
                    viewModel.selectFile()
                }
                if viewModel.droppedFileURL != nil {
                    Button("Clear") {
                        viewModel.clearSelection()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("Paste YouTube URL...", text: $viewModel.youtubeURLText)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isRunning)

            Button("Download & Separate") {
                viewModel.startYouTubeSeparation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartYouTube)

            if !viewModel.youtubeURLText.isEmpty {
                Button("Clear") {
                    viewModel.clearYouTubeURL()
                }
                .disabled(viewModel.isRunning)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preset", selection: $viewModel.selectedPreset) {
                ForEach(viewModel.supportedPresets) { preset in
                    Text(preset.displayName)
                        .tag(preset)
                        .help(preset.shortDescription)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Output: \(viewModel.outputFolderURL.path)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose Output Folder...") {
                    viewModel.pickOutputFolder()
                }
            }

            HStack(spacing: 12) {
                Button("Start Separation") {
                    viewModel.startSeparation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)

                Button("Cancel") {
                    viewModel.cancelSeparation()
                }
                .disabled(!viewModel.canCancel)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: viewModel.isRunning ? viewModel.progress : 0)
                .opacity(viewModel.isRunning ? 1 : 0)
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var errorBanner: some View {
        Group {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var resultsList: some View {
        List(viewModel.results) { item in
            HStack {
                Image(systemName: "waveform")
                VStack(alignment: .leading) {
                    Text(item.fileURL.lastPathComponent)
                        .lineLimit(1)
                    if let role = item.metadata["displayName"] {
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Reveal") {
                    viewModel.reveal(item: item)
                }
                .buttonStyle(.borderless)
            }
            .onDrag {
                guard let url = viewModel.dragURL(for: item) else {
                    return NSItemProvider()
                }
                return NSItemProvider(object: url as NSURL)
            }
        }
        .listStyle(.plain)
        .frame(minHeight: 80)
    }
}
