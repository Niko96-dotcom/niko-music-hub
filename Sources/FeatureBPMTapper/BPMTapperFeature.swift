import AppCore
import SwiftUI

public struct BPMTapperFeature: ToolFeature {
    public let metadata = ToolMetadata(
        id: "bpm-tapper",
        displayName: "BPM Tapper",
        shortLabel: "BPM Tapper",
        systemImage: "metronome",
        capabilities: []
    )

    /// Owns the tap session so leaving the tab does not wipe an in-progress tempo run.
    private final class Session: @unchecked Sendable {
        @MainActor var viewModel: BPMTapperViewModel?
    }

    private let session = Session()

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(BPMTapperView(context: context, viewModel: viewModel(for: context)))
    }

    @MainActor
    private func viewModel(for context: ToolContext) -> BPMTapperViewModel {
        if let viewModel = session.viewModel {
            return viewModel
        }
        let viewModel = BPMTapperViewModel(
            historyStore: UserDefaultsBPMHistoryStore(preferences: context.preferences),
            clipboard: PasteboardBPMClipboard()
        )
        session.viewModel = viewModel
        return viewModel
    }
}
