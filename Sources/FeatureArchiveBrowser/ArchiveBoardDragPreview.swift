import AppCore
import NikoMusicCore
import SwiftUI

/// The drag image of a board row: the row itself (the same text, marks and
/// insets at the same width) on the selection pill over the lane's surface,
/// opaque so it reads over anything while it moves. It has no hover state,
/// buttons or observed model, so the lifted row doesn't capture an in-flight
/// hover animation or change its contents while it moves.
struct ArchiveBoardDragPreview: View {
    let song: Song

    var body: some View {
        HStack(spacing: 8) {
            ArchiveBoardRowText(song: song)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !song.displayScanWarnings().isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HubDesignSystem.Palette.warning)
            }
            if song.mainPreviewURL != nil {
                // The play button's place; a landed row shows no glyph there.
                Color.clear.frame(width: ArchiveBoardCardView.playTarget, height: ArchiveBoardCardView.playTarget)
            } else {
                Image(systemName: "speaker.slash")
            }
        }
        .padding(ArchiveBoardCardView.rowPadding)
        .frame(width: ArchiveBoardLaneLayout.rowWidth, alignment: .leading)
        .background {
            ZStack {
                HubDesignSystem.Palette.surface
                HubDesignSystem.Palette.selection
            }
            .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
            .padding(.bottom, 1)
        }
    }
}
