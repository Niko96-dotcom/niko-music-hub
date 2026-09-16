import SwiftUI

public enum HubWaveformSurfaceVariant: Sendable {
    case archivePreview
    /// Thin list-row peak strip (selected/playing song cards). Not a card.
    case rowStrip
    case meter
    case empty
}

public struct HubWaveformSurface: View {
    private let peaks: [Double]
    private let progress: Double
    private let variant: HubWaveformSurfaceVariant
    private let isEnabled: Bool
    private let showsSurface: Bool

    public init(
        peaks: [Double],
        progress: Double = 0,
        variant: HubWaveformSurfaceVariant = .archivePreview,
        isEnabled: Bool = true,
        showsSurface: Bool = true,
        onSeek _: ((Double) -> Void)? = nil
    ) {
        self.peaks = peaks
        self.progress = progress
        self.variant = variant
        self.isEnabled = isEnabled
        self.showsSurface = showsSurface
    }

    public var body: some View {
        // Row strips stay unboxed — a carded 72pt hero popping into a list row is the
        // delayed "ugly player" users see on song select.
        let shouldSurface = showsSurface && variant != .rowStrip
        if shouldSurface {
            waveformContent
                .padding(variant == .meter ? 6 : 8)
                .hubCard(
                    cornerRadius: HubDesignSystem.Radius.row,
                    state: isEnabled ? .normal : .disabled,
                    interactive: isEnabled
                )
        } else {
            waveformContent
        }
    }

    private var waveformContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if normalizedPeaks.isEmpty || variant == .empty {
                    emptyState
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Canvas { context, size in
                        drawPeaks(context: &context, size: size)
                    }

                    if clampedProgress > 0 {
                        Rectangle()
                            .fill(HubDesignSystem.Palette.accent.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: clampedProgress * geometry.size.width)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .frame(height: height)
    }

    private var emptyState: some View {
        Group {
            if variant == .rowStrip {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HubDesignSystem.Palette.textTertiary.opacity(0.12))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 13, weight: .medium))
                    Text("No waveform")
                        .font(HubDesignSystem.Typography.caption())
                }
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalizedPeaks: [Double] {
        peaks.map { min(max($0.isFinite ? $0 : 0, 0), 1) }
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress.isFinite ? progress : 0, 0), 1))
    }

    private var height: CGFloat {
        switch variant {
        case .archivePreview:
            return 72
        case .rowStrip:
            return 22
        case .meter:
            return 44
        case .empty:
            return 54
        }
    }

    private func drawPeaks(context: inout GraphicsContext, size: CGSize) {
        let values = normalizedPeaks
        guard !values.isEmpty else { return }

        let barWidth = size.width / CGFloat(values.count)
        let midY = size.height / 2
        for (index, peak) in values.enumerated() {
            let amplitude: CGFloat = {
                switch variant {
                case .meter: return 0.78
                case .rowStrip: return 0.92
                case .archivePreview, .empty: return 0.90
                }
            }()
            let height = CGFloat(peak) * size.height * amplitude
            let x = CGFloat(index) * barWidth
            let rect = CGRect(
                x: x + barWidth * 0.15,
                y: midY - height / 2,
                width: max(barWidth * 0.7, 1),
                height: max(height, variant == .meter ? 1 : 2)
            )
            let played = Double(index) / Double(values.count) <= Double(clampedProgress)
            context.fill(
                Path(roundedRect: rect, cornerSize: CGSize(width: 1.5, height: 1.5)),
                with: .color(played ? HubDesignSystem.Palette.accent : barColor)
            )
        }
    }

    private var barColor: Color {
        switch variant {
        case .archivePreview:
            return Color.secondary.opacity(0.58)
        case .rowStrip:
            return HubDesignSystem.Palette.textTertiary.opacity(0.72)
        case .meter:
            return HubDesignSystem.Palette.accent.opacity(0.62)
        case .empty:
            return Color.secondary.opacity(0.30)
        }
    }
}

public enum HubMediaSurfaceFixtures {
    public static let archivePreviewPeaks: [Double] = [
        0.20, 0.42, 0.65, 0.38, 0.78, 0.92, 0.56, 0.34,
        0.48, 0.72, 0.88, 0.64, 0.35, 0.52, 0.70, 0.44,
    ]

    public static let meterPeaks: [Double] = [
        0.10, 0.24, 0.52, 0.80, 0.58, 0.36, 0.62, 0.90,
        0.76, 0.48, 0.28, 0.18,
    ]
}
