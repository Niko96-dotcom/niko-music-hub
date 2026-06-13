import AppCore
import SwiftUI

public struct StemSeparationFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: StemSeparationService.toolID,
        displayName: "Stem Separation",
        shortLabel: "Stems",
        systemImage: "slider.horizontal.below.rectangle",
        capabilities: [.producesFiles, .runsJobs]
    )

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        let backend = DemucsMLXBackend(settings: (try? context.settingsStore.loadSettings().helperTools) ?? HelperToolSettings())
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: context.outputInboxStore,
            jobRunner: context.jobRunner
        )
        let viewModel = StemSeparationViewModel(
            context: context,
            service: service
        )
        return AnyView(StemSeparationView(viewModel: viewModel))
    }
}
