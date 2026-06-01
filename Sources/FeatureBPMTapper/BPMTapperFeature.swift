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

    public init() {}

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        AnyView(BPMTapperView(
            context: context,
            viewModel: BPMTapperViewModel(
                historyStore: UserDefaultsBPMHistoryStore(),
                clipboard: PasteboardBPMClipboard()
            )
        ))
    }
}
