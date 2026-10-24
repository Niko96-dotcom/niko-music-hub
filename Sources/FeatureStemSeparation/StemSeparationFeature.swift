import AppCore
import FeatureDownloader
import SwiftUI

public struct StemSeparationFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: .stemSeparation,
        displayName: "Stem Separation",
        shortLabel: "Stems",
        systemImage: "slider.horizontal.below.rectangle",
        handlesEscape: true
    )

    /// Owns the tool session so tab switches reuse backends/workflows instead of rebuilding them.
    private final class Session: @unchecked Sendable {
        @MainActor var viewModel: StemSeparationViewModel?
    }

    private let session = Session()

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(StemSeparationView(viewModel: viewModel(for: context)))
    }

    @MainActor
    private func viewModel(for context: ToolContext) -> StemSeparationViewModel {
        if let viewModel = session.viewModel {
            return viewModel
        }
        let settingsStore = context.settingsStore
        let helperProbe = context.helperHealth.probe
        let backend = DemucsMLXBackend(
            commandBuilder: DemucsMLXCommandBuilder(locator: helperProbe.locator),
            settingsProvider: {
                try settingsStore.loadSettings().helperTools
            }
        )
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: context.outputInboxStore,
            jobRunner: context.jobRunner
        )
        let downloaderUseCase = DownloaderUseCase(
            downloader: YtDlpDownloader(),
            helperProbe: helperProbe,
            jobRunner: context.jobRunner,
            settingsStore: context.settingsStore
        )
        let youtubeWorkflow = YouTubeStemSeparationWorkflow(
            downloader: YtDlpYouTubeAudioDownloader(useCase: downloaderUseCase),
            stemService: service,
            jobRunner: context.jobRunner
        )
        let viewModel = StemSeparationViewModel(
            context: context,
            service: service,
            youtubeWorkflow: youtubeWorkflow
        )
        session.viewModel = viewModel
        return viewModel
    }

    /// Test seam: proves tab remounts reuse one StemSeparationViewModel session.
    @MainActor
    var sessionViewModelForTesting: StemSeparationViewModel? {
        session.viewModel
    }
}
