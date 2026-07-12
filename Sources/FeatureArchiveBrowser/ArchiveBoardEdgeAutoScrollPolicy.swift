import CoreGraphics

/// Decides whether a board drag is close enough to a horizontal edge to move
/// the viewport by one workflow lane. Keeping this independent from SwiftUI
/// makes the edge behavior deterministic and easy to exercise in tests.
enum ArchiveBoardEdgeAutoScrollPolicy {
    /// Wide enough to reach deliberately while dragging, without making the
    /// outer parts of normal lanes unexpectedly scroll the board.
    static let activationInset: CGFloat = 56

    static func targetColumnIndex(
        pointerX: CGFloat,
        viewportWidth: CGFloat,
        leadingColumnIndex: Int,
        columnCount: Int
    ) -> Int? {
        guard columnCount > 1, viewportWidth > activationInset * 2 else { return nil }

        if pointerX <= activationInset {
            let target = max(0, leadingColumnIndex - 1)
            return target == leadingColumnIndex ? nil : target
        }

        if pointerX >= viewportWidth - activationInset {
            let target = min(columnCount - 1, leadingColumnIndex + 1)
            return target == leadingColumnIndex ? nil : target
        }

        return nil
    }
}
