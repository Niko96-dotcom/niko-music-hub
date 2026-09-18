import Foundation

/// Drives the board's horizontal viewport one lane at a time while a dragged
/// card is held at an edge; `ArchiveBoardEdgeAutoScrollPolicy` decides when.
@MainActor
final class ArchiveBoardEdgeAutoScroller {
    enum Direction {
        case left
        case right
    }

    private var task: Task<Void, Never>?
    private var direction: Direction?
    private var nextColumnIndex = 0

    func update(
        pointerX: CGFloat,
        viewportWidth: CGFloat,
        leadingColumnIndex: Int,
        columnCount: Int,
        scrollTo: @escaping (Int, Direction) -> Void
    ) {
        guard let target = ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
            pointerX: pointerX,
            viewportWidth: viewportWidth,
            leadingColumnIndex: leadingColumnIndex,
            columnCount: columnCount
        ) else {
            stop()
            return
        }

        let requestedDirection: Direction = target > leadingColumnIndex ? .right : .left
        guard requestedDirection != direction || task == nil else { return }

        stop()
        direction = requestedDirection
        nextColumnIndex = leadingColumnIndex
        advance(columnCount: columnCount, scrollTo: scrollTo)

        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled, let self else { return }
                self.advance(columnCount: columnCount, scrollTo: scrollTo)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        direction = nil
    }

    private func advance(
        columnCount: Int,
        scrollTo: @escaping (Int, Direction) -> Void
    ) {
        guard let direction else {
            stop()
            return
        }

        let target = switch direction {
        case .left: max(0, nextColumnIndex - 1)
        case .right: min(columnCount - 1, nextColumnIndex + 1)
        }
        guard target != nextColumnIndex else {
            stop()
            return
        }

        nextColumnIndex = target
        scrollTo(target, direction)
    }
}
