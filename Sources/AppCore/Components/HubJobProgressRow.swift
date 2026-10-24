import SwiftUI

/// A running job on a tool page (design contract §4): a bar, an optional meter
/// line and an optional status line, inside the page's fixed primary object.
///
/// The bar is indeterminate while `fraction` is nil. The meter line exists when
/// `startedAt` is set: `NN% complete` (with a fraction) and `Elapsed m:ss`.
public struct HubJobProgressRow: View {
    private let fraction: Double?
    private let status: String?
    private let startedAt: Date?

    public init(fraction: Double?, status: String?, startedAt: Date? = nil) {
        self.fraction = fraction
        self.status = status
        self.startedAt = startedAt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(HubDesignSystem.Colors.indicator)

            if let startedAt {
                HStack {
                    if let fraction {
                        Text("\(Int(fraction * 100))% complete")
                    }
                    Spacer()
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Self.elapsedCaption(since: startedAt, now: context.date))
                    }
                }
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }

            if let status {
                Text(status)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `Elapsed m:ss` since `start`; a start in the future reads `Elapsed 0:00`.
    public nonisolated static func elapsedCaption(since start: Date, now: Date) -> String {
        let totalSeconds = Int(max(0, now.timeIntervalSince(start)))
        return String(format: "Elapsed %d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
