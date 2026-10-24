import AppCore
import SwiftUI

public struct AudioRecorderFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: .audioRecorder,
        displayName: "Audio Recorder",
        shortLabel: "Recorder",
        systemImage: "waveform.circle"
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
        let viewModel = Self.makeViewModel(context: context, capturePort: CoreAudioTapAdapter())
        session.viewModel = viewModel
        return viewModel
    }

    /// The recorder wired to the app's context. Tests pass a fake capture port instead of CoreAudio.
    @MainActor
    static func makeViewModel(context: ToolContext, capturePort: AudioCapturePort) -> AudioRecorderViewModel {
        // Display-only value from the shared observer. Anything that gates a
        // write goes through `destinationProvider` below.
        let settings = context.appSettings.settings
        return AudioRecorderViewModel(
            capturePort: capturePort,
            useCase: RecordSystemAudioUseCase(capturePort: capturePort),
            destinationProvider: { try ToolOutputDestination.load(from: context.settingsStore) },
            outputInboxStore: context.outputInboxStore,
            initialMaxDurationMinutes: RecordingDurationOptions.normalized(settings.maxRecordingDurationMinutes),
            jobStatusCenter: context.jobStatusCenter,
            audioCaptureActivity: context.audioCaptureActivity
        )
    }
}
