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

    /// Owns the converter session so queued files survive tab switches.
    private final class Session: @unchecked Sendable {
        @MainActor var viewModel: AudioConverterViewModel?
    }

    private let session = Session()

    public init(router: QuickAccessRouter? = nil) {
        self.router = router
    }

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(AudioConverterView(
            context: context,
            viewModel: viewModel(for: context)
        ))
    }

    @MainActor
    private func viewModel(for context: ToolContext) -> AudioConverterViewModel {
        if let viewModel = session.viewModel {
            return viewModel
        }
        let viewModel = AudioConverterViewModel(context: context)
        if let router {
            viewModel.bindConverterHandoff(to: router)
        }
        session.viewModel = viewModel
        return viewModel
    }
}
