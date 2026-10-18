import AppCore
import NikoMusicCore
import SwiftUI

/// Most recent workflow status changes, newest first, or the empty line.
struct SongStatusHistoryList: View {
    let history: [WorkflowStatusChange]

    struct Row: Identifiable {
        let id: String
        let change: WorkflowStatusChange
    }

    /// Rows keyed by timestamp plus an ordinal among same-instant changes, so
    /// identity stays stable across inserts and never collides. `history`
    /// arrives oldest first; ordinals are assigned in that order, then the
    /// rows are reversed so the newest change is shown first.
    var rows: [Row] {
        var ordinals: [Date: Int] = [:]
        let oldestFirst = history.map { change in
            let ordinal = ordinals[change.changedAt, default: 0]
            ordinals[change.changedAt] = ordinal + 1
            return Row(id: "\(change.changedAt.timeIntervalSinceReferenceDate)#\(ordinal)", change: change)
        }
        return oldestFirst.reversed()
    }

    var body: some View {
        if history.isEmpty {
            Text("No status changes recorded yet.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    Text("\(row.change.toStatus?.displayTitle ?? "No Status") · \(HubRelativeTime.string(for: row.change.changedAt))")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
            }
        }
    }
}
