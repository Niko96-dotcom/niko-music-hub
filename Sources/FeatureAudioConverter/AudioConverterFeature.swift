import AppCore
import SwiftUI

public struct AudioConverterFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "wav-converter",
        displayName: "WAV Converter",
        shortLabel: "WAV Converter",
        systemImage: "waveform",
        capabilities: [.producesFiles, .runsJobs]
    )

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(AudioConverterView(
            context: context,
            viewModel: AudioConverterViewModel(context: context)
        ))
    }
}
