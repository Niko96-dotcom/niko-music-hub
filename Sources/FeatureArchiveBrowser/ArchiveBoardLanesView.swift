import SwiftUI

/// The native row of workflow lanes and its drag edge auto-scroller.
struct ArchiveBoardLanesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    let columns: [ArchiveBoardColumn]
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let compactEmptyStages: Bool
    /// Called when a card or lane is clicked, so the board can reclaim keyboard focus.
    let onInteract: () -> Void

    @State private var scrolling = ArchiveBoardScrollController()
    @State private var edgeAutoScroller = ArchiveBoardEdgeAutoScroller()

    var body: some View {
        let compactIDs = Set(columns.filter { column in
            compactEmptyStages && !viewModel.songs.contains { $0.workflowStatus == column.status }
        }.map(\.id))
        let presentation = ArchiveBoardLanesPresentation(
            columns: columns, compactColumnIDs: compactIDs,
            colorScheme: colorScheme, reduceMotion: reduceMotion, layoutDirection: layoutDirection,
            state: ArchiveBoardLaneState(viewModel: viewModel)
        )
        ArchiveBoardHorizontalScroll(
            controller: scrolling, presentation: presentation, viewModel: viewModel,
            onInteract: onInteract, locationChanged: handleDragLocation,
            ended: { edgeAutoScroller.stop() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A `DropInfo` location is local to the lane receiving the card. Combine
    /// it with that lane's measured board-space origin to know whether the
    /// pointer is held at the left or right edge of the visible viewport.
    private func handleDragLocation(
        columnID: String,
        localX: CGFloat
    ) {
        let origins = scrolling.columnOrigins()
        guard let pointerX = scrolling.pointerX(columnID: columnID, localX: localX) else { return }
        let leadingIndex = leadingVisibleColumnIndex(origins)
        edgeAutoScroller.update(
            pointerX: pointerX,
            viewportWidth: scrolling.viewportWidth,
            leadingColumnIndex: leadingIndex,
            columnCount: columns.count
        ) { targetIndex, _ in
            guard columns.indices.contains(targetIndex) else { return }
            scrolling.scroll(to: columns[targetIndex].id, animated: !reduceMotion)
        }
    }

    private func leadingVisibleColumnIndex(_ columnOrigins: [String: CGFloat]) -> Int {
        let origins = columns.enumerated().compactMap { index, column in
            columnOrigins[column.id].map { (index, $0) }
        }
        guard !origins.isEmpty else { return 0 }

        // Prefer the right-most lane already touching the viewport's leading
        // edge; before the first scroll, all origins are positive, so use the
        // left-most lane instead.
        if let leading = origins.filter({ $0.1 <= 0 }).max(by: { $0.1 < $1.1 }) {
            return leading.0
        }
        return origins.min(by: { $0.1 < $1.1 })?.0 ?? 0
    }
}

/// Value inputs for the retained native columns. Equality uses the existing
/// shared-storage column comparisons, without reflecting through every song.
struct ArchiveBoardLanesPresentation: Equatable {
    let columns: [ArchiveBoardColumn]
    let compactColumnIDs: Set<String>
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let layoutDirection: LayoutDirection
    let state: ArchiveBoardLaneState

}

enum ArchiveBoardLaneLayout {
    static let expandedWidth: CGFloat = 220
    static let compactWidth: CGFloat = 56
    static let spacing: CGFloat = 10
    /// Inset of a lane's header and rows from its edges.
    static let padding: CGFloat = 8
    /// Width of a row in an expanded lane, which the drag image matches.
    static let rowWidth = expandedWidth - 2 * padding

    static func documentWidth(columnIDs: [String], compactIDs: Set<String>, expandedIDs: Set<String>) -> CGFloat {
        columnIDs.reduce(0) { $0 + (compactIDs.contains($1) && !expandedIDs.contains($1) ? compactWidth : expandedWidth) }
            + CGFloat(max(0, columnIDs.count - 1)) * spacing
    }
}
