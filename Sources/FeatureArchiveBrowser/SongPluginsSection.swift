import AppCore
import SwiftUI

/// Plugins tab: names from the latest project's plugin summary once the
/// section has been expanded (the summary is fetched on expand).
struct SongPluginsSection: View {
    let isExpanded: Bool
    let pluginNames: [String]?
    /// True only when a plugin read can still complete: the song has a latest
    /// CPR but its summary has not arrived yet. False for no-project (nil CPR)
    /// and for a finished empty read, which both stay on the quiet empty line.
    let isLoading: Bool

    /// The marker and subprocess readers can repeat a plugin used on several
    /// tracks; list each name once, in the order it first appeared.
    private var uniqueNames: [String] {
        var seen: Set<String> = []
        return (pluginNames ?? []).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            if isExpanded {
                let names = uniqueNames
                if !names.isEmpty {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    }
                } else if isLoading {
                    Text("Loading plugin list…")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                } else {
                    Text("No plugin list available for this project.")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
        }
    }
}
