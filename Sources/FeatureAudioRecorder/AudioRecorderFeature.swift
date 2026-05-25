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

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(AudioRecorderView(context: context))
    }
}
