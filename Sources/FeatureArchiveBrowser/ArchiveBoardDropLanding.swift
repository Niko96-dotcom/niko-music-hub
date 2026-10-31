import AppKit
import NikoMusicCore
import SwiftUI

/// Lands a dropped song in its new lane.
///
/// AppKit's own landing (`animatesToDestination`) slid the drag image, a box
/// unlike the row, onto a row that had already faded in under it: two cards
/// overlapped, moved at different speeds, and one vanished. The board lands
/// the drop itself. The new row waits hidden in the gap its lane opens; a copy
/// of the drag image (the row with the selection pill) flies from where the
/// pointer let go into that gap; the row takes over under the copy with the
/// same pill, which then fades.
@MainActor
enum ArchiveBoardDropLanding {
    /// Fast out of the hand, then a soft settle with no overshoot.
    static let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)

    /// A short hop lands quicker than a flight across the board.
    static func flightDuration(distance: CGFloat) -> TimeInterval {
        min(0.36, max(0.2, 0.18 + Double(distance) / 2400))
    }

    /// - Parameters:
    ///   - released: the drag image's frame at release and the view it is in;
    ///     nil when AppKit did not report it.
    ///   - host: the board viewport the copy flies over.
    static func land(_ song: Song, releasedAt released: (frame: CGRect, view: NSView)?,
                     into list: ArchiveBoardNativeSongListView, over host: NSView?,
                     colorScheme: ColorScheme, reduceMotion: Bool,
                     completion: @escaping @MainActor @Sendable () -> Void = {}) {
        let songID = song.id
        guard !reduceMotion, let host, let released else {
            // Next turn: the lane has laid out the new row by then.
            DispatchQueue.main.async {
                list.finishLanding(songID: songID)
                completion()
            }
            return
        }
        list.holdLanding(songID: songID)
        let start = host.convert(released.frame, from: released.view)
        let copy = ArchiveBoardLandingCopy(
            rootView: AnyView(ArchiveBoardDragPreview(song: song).environment(\.colorScheme, colorScheme)))
        copy.sizingOptions = []
        copy.frame = start
        host.addSubview(copy, positioned: .above, relativeTo: nil)
        // The drop returns with layout still to come (the released lane can
        // collapse and shift the board), so aim at the row on the next turn.
        DispatchQueue.main.async {
            guard let target = list.landingFrame(songID: songID, in: host) else {
                return settle(songID, copy: copy, list: list, completion: completion)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = flightDuration(distance: hypot(target.midX - start.midX, target.midY - start.midY))
                context.timingFunction = curve
                copy.animator().frame = target
            } completionHandler: {
                MainActor.assumeIsolated { settle(songID, copy: copy, list: list, completion: completion) }
            }
        }
    }

    /// The row takes over under the copy, which then goes.
    private static func settle(_ songID: String, copy: NSView, list: ArchiveBoardNativeSongListView,
                               completion: @MainActor @Sendable () -> Void) {
        list.finishLanding(songID: songID)
        copy.removeFromSuperview()
        completion()
    }
}

/// The flying copy of a dropped row. It takes no clicks.
final class ArchiveBoardLandingCopy: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
