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

    private let router: QuickAccessRouter?

    public init(router: QuickAccessRouter? = nil) {
        self.router = router
    }

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(AudioConverterView(
            context: context,
            viewModel: AudioConverterViewModel(context: context),
            router: router
        ))
    }
}
