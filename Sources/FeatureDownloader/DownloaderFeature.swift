import AppCore
import SwiftUI

public struct DownloaderFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "downloader",
        displayName: "Downloader",
        shortLabel: "Downloader",
        systemImage: "arrow.down.circle",
        capabilities: [.producesFiles, .runsJobs]
    )

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        let healthChecker = YtDlpHealthChecker()
        let downloader = YtDlpDownloader()
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker,
            jobRunner: context.jobRunner,
            settingsStore: context.settingsStore
        )
        let viewModel = DownloaderViewModel(context: context, useCase: useCase, healthChecker: healthChecker)
        return AnyView(DownloaderView(context: context, viewModel: viewModel))
    }
}