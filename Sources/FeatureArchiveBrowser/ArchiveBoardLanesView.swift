import AppCore
import SwiftUI

/// The horizontally scrolling row of workflow lanes. Owns the lane-origin
/// measurements and the edge auto-scroller so a card dragged to the viewport's
/// left or right edge walks the board one lane at a time.
struct ArchiveBoardLanesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let columns: [ArchiveBoardColumn]
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let compactEmptyStages: Bool
    /// Called when a card or lane is clicked, so the board can reclaim keyboard focus.
    let onInteract: () -> Void

    @State private var columnOrigins: [String: CGFloat] = [:]
    @State private var boardViewportWidth: CGFloat = 0
    @State private var edgeAutoScroller = ArchiveBoardEdgeAutoScroller()

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns) { column in
                        ArchiveBoardColumnView(
                            column: column,
                            viewModel: viewModel,
                            compactWhenEmpty: compactEmptyStages && !viewModel.songs.contains { $0.workflowStatus == column.status },
                            onDragLocationChanged: { columnID, localX in
                                handleDragLocation(
                                    columnID: columnID,
                                    localX: localX,
                                    scrollProxy: scrollProxy
                                )
                            },
                            onDragEnded: {
                                edgeAutoScroller.stop()
                            },
                            onInteract: onInteract
                        )
                        .id(column.id)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ArchiveBoardColumnOriginPreferenceKey.self,
                                    value: [column.id: proxy.frame(in: .named(ArchiveBoardCoordinateSpace.name)).minX]
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .coordinateSpace(name: ArchiveBoardCoordinateSpace.name)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            boardViewportWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size) { _, size in
                            boardViewportWidth = size.width
                        }
                }
            }
            .onPreferenceChange(ArchiveBoardColumnOriginPreferenceKey.self) { origins in
                columnOrigins = origins
            }
        }
    }

    /// A `DropInfo` location is local to the lane receiving the card. Combine
    /// it with that lane's measured board-space origin to know whether the
    /// pointer is held at the left or right edge of the visible viewport.
    private func handleDragLocation(
        columnID: String,
        localX: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
        guard let columnX = columnOrigins[columnID] else { return }
        let leadingIndex = leadingVisibleColumnIndex()
        edgeAutoScroller.update(
            pointerX: columnX + localX,
            viewportWidth: boardViewportWidth,
            leadingColumnIndex: leadingIndex,
            columnCount: columns.count
        ) { targetIndex, direction in
            guard columns.indices.contains(targetIndex) else { return }
            let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
            let scroll = {
                scrollProxy.scrollTo(
                    columns[targetIndex].id,
                    anchor: direction == .right ? .leading : .trailing
                )
            }
            if duration == 0 {
                scroll()
            } else {
                withAnimation(.easeOut(duration: duration)) {
                    scroll()
                }
            }
        }
    }

    private func leadingVisibleColumnIndex() -> Int {
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

private enum ArchiveBoardCoordinateSpace {
    static let name = "archive-board-viewport"
}

private struct ArchiveBoardColumnOriginPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
