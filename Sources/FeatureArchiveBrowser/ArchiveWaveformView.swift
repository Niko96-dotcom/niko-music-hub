import AppCore
import SwiftUI

struct ArchiveWaveformView: View {
    let peaks: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    drawWaveform(context: &context, size: size)
                }
                if progress > 0, progress.isFinite {
                    Rectangle()
                        .fill(HubDesignSystem.Colors.accent.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: CGFloat(progress) * geometry.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(0, value.location.x / max(geometry.size.width, 1)), 1)
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: 72)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty else { return }
        let barWidth = size.width / CGFloat(peaks.count)
        let midY = size.height / 2
        for (index, peak) in peaks.enumerated() {
            let height = CGFloat(peak) * size.height * 0.9
            let x = CGFloat(index) * barWidth
            let rect = CGRect(
                x: x + barWidth * 0.15,
                y: midY - height / 2,
                width: max(barWidth * 0.7, 1),
                height: max(height, 2)
            )
            let played = Double(index) / Double(peaks.count) <= progress
            context.fill(
                Path(roundedRect: rect, cornerSize: CGSize(width: 1, height: 1)),
                with: .color(played ? HubDesignSystem.Colors.accent : Color.secondary.opacity(0.55))
            )
        }
    }
}
