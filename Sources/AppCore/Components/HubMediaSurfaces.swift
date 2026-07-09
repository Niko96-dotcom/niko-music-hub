import SwiftUI

public enum HubTransportBarStyle: Sendable {
    case compact
    case full
}

public struct HubTransportBar: View {
    private let style: HubTransportBarStyle
    private let title: String
    private let subtitle: String?
    private let isPlaying: Bool
    private let currentTime: Double
    private let duration: Double
    private let isEnabled: Bool
    private let markerProgress: Double?
    private let volumeLevel: Double?
    private let showsSkipControls: Bool
    private let showsSurface: Bool
    private let showsSlider: Bool
    private let onPlayPause: () -> Void
    private let onSeekBackward: (() -> Void)?
    private let onSeekForward: (() -> Void)?
    private let onSeek: (Double) -> Void

    public init(
        style: HubTransportBarStyle = .full,
        title: String,
        subtitle: String? = nil,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        isEnabled: Bool = true,
        markerProgress: Double? = nil,
        volumeLevel: Double? = nil,
        showsSkipControls: Bool = false,
        showsSurface: Bool = true,
        showsSlider: Bool = true,
        onPlayPause: @escaping () -> Void,
        onSeekBackward: (() -> Void)? = nil,
        onSeekForward: (() -> Void)? = nil,
        onSeek: @escaping (Double) -> Void
    ) {
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.isEnabled = isEnabled
        self.markerProgress = markerProgress
        self.volumeLevel = volumeLevel
        self.showsSkipControls = showsSkipControls
        self.showsSurface = showsSurface
        self.showsSlider = showsSlider
        self.onPlayPause = onPlayPause
        self.onSeekBackward = onSeekBackward
        self.onSeekForward = onSeekForward
        self.onSeek = onSeek
    }

    public var body: some View {
        if showsSurface {
            content
                .padding(style == .compact ? 6 : 10)
                .hubCard(
                    cornerRadius: HubDesignSystem.Radius.row,
                    state: isEnabled ? .normal : .disabled,
                    interactive: isEnabled
                )
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 4 : 8) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                if showsSkipControls {
                    transportButton(
                        systemImage: "gobackward.5",
                        accessibilityLabel: "Back five seconds",
                        prominent: false,
                        action: onSeekBackward ?? {}
                    )
                }

                transportButton(
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    accessibilityLabel: isPlaying ? "Pause preview" : "Play preview",
                    prominent: true,
                    action: onPlayPause
                )

                if showsSkipControls {
                    transportButton(
                        systemImage: "goforward.5",
                        accessibilityLabel: "Forward five seconds",
                        prominent: false,
                        action: onSeekForward ?? {}
                    )
                }

                if !title.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(style == .compact
                                  ? HubDesignSystem.Typography.caption().weight(.medium)
                                  : HubDesignSystem.Typography.bodySmall().weight(.medium))
                            .foregroundStyle(
                                isEnabled
                                    ? HubDesignSystem.Palette.textPrimary
                                    : HubDesignSystem.Palette.textTertiary
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if style == .full, let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(HubDesignSystem.Typography.micro())
                                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if style == .full {
                    trailingStatus
                }
            }

            if showsSlider, isEnabled, duration > 0 {
                progressSlider
            }
        }
    }

    private var trailingStatus: some View {
        HStack(spacing: 6) {
            if let volumeLevel {
                Image(systemName: volumeIcon(for: volumeLevel))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .accessibilityLabel("Volume ready")
            }

            Text(timeLabel(current: currentTime, total: duration))
                .font(HubDesignSystem.Typography.mono(size: 10))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var progressSlider: some View {
        let safeDuration = max(duration, 0.1)

        return ZStack(alignment: .leading) {
            Slider(
                value: Binding(
                    get: { clamped(currentTime, lower: 0, upper: safeDuration) },
                    set: { onSeek(clamped($0, lower: 0, upper: safeDuration)) }
                ),
                in: 0...safeDuration
            )
            .controlSize(style == .compact ? .mini : .small)
            .accessibilityLabel("Preview position")

            if let markerProgress {
                GeometryReader { geometry in
                    let progress = clamped(markerProgress, lower: 0, upper: 1)
                    let x = CGFloat(progress) * geometry.size.width
                    Rectangle()
                        .fill(HubDesignSystem.Palette.accent.opacity(0.85))
                        .frame(width: 2, height: geometry.size.height + 4)
                        .offset(x: max(0, x - 1))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: style == .compact ? 16 : 22)
    }

    private func transportButton(
        systemImage: String,
        accessibilityLabel: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent && isPlaying {
                // Solid amber only while actively playing — the one focal accent (art direction:
                // "accent reserved for active playback"; references use accent sparingly).
                Button(action: action) {
                    transportButtonIcon(systemImage)
                }
                .buttonStyle(.borderedProminent)
                .tint(HubDesignSystem.Palette.accent)
            } else if prominent {
                // Idle play affordance: restrained tinted capsule, not a solid accent block.
                Button(action: action) {
                    transportButtonIcon(systemImage)
                }
                .buttonStyle(.bordered)
                .tint(HubDesignSystem.Palette.accent)
            } else {
                Button(action: action) {
                    transportButtonIcon(systemImage)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(style == .compact ? .mini : .small)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func transportButtonIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: style == .compact ? 11 : 13, weight: .semibold))
            .frame(width: style == .compact ? 24 : 28, height: style == .compact ? 24 : 28)
    }

    private func timeLabel(current: Double, total: Double) -> String {
        "\(formatTime(current)) / \(formatTime(total))"
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let whole = Int(value.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func volumeIcon(for level: Double) -> String {
        switch clamped(level, lower: 0, upper: 1) {
        case 0:
            return "speaker.slash.fill"
        case 0..<0.34:
            return "speaker.wave.1.fill"
        case 0.34..<0.72:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value.isFinite ? value : lower, lower), upper)
    }
}

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
    private let onSeek: ((Double) -> Void)?

    public init(
        peaks: [Double],
        progress: Double = 0,
        variant: HubWaveformSurfaceVariant = .archivePreview,
        isEnabled: Bool = true,
        showsSurface: Bool = true,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.peaks = peaks
        self.progress = progress
        self.variant = variant
        self.isEnabled = isEnabled
        self.showsSurface = showsSurface
        self.onSeek = onSeek
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, !(normalizedPeaks.isEmpty || variant == .empty), let onSeek else { return }
                        let fraction = min(max(0, value.location.x / max(geometry.size.width, 1)), 1)
                        onSeek(Double(fraction))
                    }
            )
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
