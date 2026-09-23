import AppCore
import SwiftUI

/// Way out of the fail-closed song-detail gate (D2). One song in the detail
/// pane, or every blocked song from the footer strip. The repair itself keeps
/// every readable detail and clears only lists that can't be read.
struct SongMetadataRepairNotice: View {
    enum Scope {
        case song(id: String)
        case all
    }

    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let scope: Scope

    static let repairLabel = "Repair Song Details"

    private var songIDs: [String] {
        switch scope {
        case .song(let id):
            return viewModel.metadataRepairSongIDs.contains(id) ? [id] : []
        case .all:
            return viewModel.metadataRepairSongIDs.sorted()
        }
    }

    private var message: String {
        switch scope {
        case .song:
            return "Some details for this song couldn't be read, so changes to it are paused."
        case .all:
            let count = viewModel.metadataRepairSongIDs.count
            return count == 1
                ? "Details for 1 song couldn't be read, so changes to it are paused."
                : "Details for \(count) songs couldn't be read, so changes to them are paused."
        }
    }

    var body: some View {
        let ids = songIDs
        if !ids.isEmpty {
            HStack(spacing: 10) {
                Text(message)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HubLabeledButton(
                    icon: "wrench.and.screwdriver",
                    label: Self.repairLabel,
                    style: .secondary,
                    help: "Keeps every detail that can be read and clears only the lists that can't"
                ) {
                    viewModel.repairSongMetadata(songIDs: ids)
                }
            }
        }
    }
}
