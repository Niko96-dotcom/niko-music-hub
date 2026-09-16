import AppCore
import FeatureDownloader
import SwiftUI

public struct StemSeparationFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: StemSeparationService.toolID,
        displayName: "Stem Separation",
        shortLabel: "Stems",
        systemImage: "slider.horizontal.below.rectangle",
        capabilities: [.producesFiles, .runsJobs]
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
        let backend = DemucsMLXBackend(
            settingsProvider: {
                (try? settingsStore.loadSettings().helperTools) ?? HelperToolSettings()
            }
        )
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: context.outputInboxStore,
            jobRunner: context.jobRunner,
            archiveRootsProvider: {
                try context.settingsStore.loadSettings().archiveRoots.map(\.url)
            }
        )
        let healthChecker = YtDlpHealthChecker()
        let downloaderUseCase = DownloaderUseCase(
            downloader: YtDlpDownloader(),
            healthChecker: healthChecker,
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
