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

    /// Owns the tool session so tab switches reuse the downloader stack.
    private final class Session: @unchecked Sendable {
        @MainActor var viewModel: DownloaderViewModel?
    }

    private let session = Session()

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(DownloaderView(context: context, viewModel: viewModel(for: context)))
    }

    @MainActor
    private func viewModel(for context: ToolContext) -> DownloaderViewModel {
        if let viewModel = session.viewModel {
            return viewModel
        }
        let healthChecker = YtDlpHealthChecker()
        let useCase = DownloaderUseCase(
            downloader: YtDlpDownloader(),
            healthChecker: healthChecker,
            jobRunner: context.jobRunner,
            settingsStore: context.settingsStore
        )
        let viewModel = DownloaderViewModel(context: context, useCase: useCase, healthChecker: healthChecker)
        session.viewModel = viewModel
        return viewModel
    }
}