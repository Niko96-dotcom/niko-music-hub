import AppCore
import SwiftUI

public struct AudioRecorderFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "audio-recorder",
        displayName: "Audio Recorder",
        shortLabel: "Recorder",
        systemImage: "waveform.circle",
        capabilities: [.producesFiles, .runsJobs]
    )

    /// Owns the recorder session so CoreAudio setup is not rebuilt on every tab visit.
    private final class Session: @unchecked Sendable {
        @MainActor var viewModel: AudioRecorderViewModel?
    }

    private let session = Session()

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(AudioRecorderView(context: context, viewModel: viewModel(for: context)))
    }

    @MainActor
    private func viewModel(for context: ToolContext) -> AudioRecorderViewModel {
        if let viewModel = session.viewModel {
            return viewModel
        }
        let capturePort = CoreAudioTapAdapter()
        let useCase = RecordSystemAudioUseCase(
            capturePort: capturePort,
            archiveRootsProvider: {
                let settings = (try? context.settingsStore.loadSettings()) ?? .default
                return settings.archiveRoots.map(\.url)
            }
        )
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let viewModel = AudioRecorderViewModel(
            capturePort: capturePort,
            useCase: useCase,
            outputURLProvider: {
                let settings = (try? context.settingsStore.loadSettings()) ?? .default
                return settings.outputFolder.url
            },
            outputInboxStore: context.outputInboxStore,
            initialMaxDurationMinutes: RecordingDurationOptions.normalized(settings.maxRecordingDurationMinutes)
        )
        session.viewModel = viewModel
        return viewModel
    }
}
