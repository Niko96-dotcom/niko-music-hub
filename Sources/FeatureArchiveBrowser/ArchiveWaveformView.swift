import AppCore
import SwiftUI

struct ArchiveWaveformView: View {
    let peaks: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        HubWaveformSurface(
            peaks: peaks.map(Double.init),
            progress: progress,
            variant: peaks.isEmpty ? .empty : .archivePreview,
            isEnabled: !peaks.isEmpty,
            onSeek: onSeek
        )
    }
}
