import AppCore
import SwiftUI

struct ArchiveWaveformView: View {
    let peaks: [Float]
    let progress: Double
    var variant: HubWaveformSurfaceVariant = .archivePreview
    /// When nil, surfaces are shown for hero/meter variants and hidden for row strips.
    var showsSurface: Bool? = nil
    let onSeek: (Double) -> Void

    var body: some View {
        let resolvedVariant: HubWaveformSurfaceVariant = {
            if peaks.isEmpty {
                return variant == .rowStrip ? .rowStrip : .empty
            }
            return variant
        }()
        let resolvedSurface = showsSurface ?? (variant != .rowStrip)

        HubWaveformSurface(
            peaks: peaks.map(Double.init),
            progress: progress,
            variant: resolvedVariant,
            isEnabled: !peaks.isEmpty,
            showsSurface: resolvedSurface,
            onSeek: onSeek
        )
    }
}
