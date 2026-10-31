import AppCore
import AppKit
import ProjectVaultRuntime
import SwiftUI

/// SwiftUI's DropDelegate cannot read where the drag image was let go.
/// This boundary hosts one column and hands that frame to the board's landing
/// (`ArchiveBoardDropLanding`).
struct ArchiveBoardDropHost<Content: View>: NSViewRepresentable {
    let content: Content
    let renderKey: ArchiveBoardColumnRenderKey
    let accepts: (String) -> Bool
    /// False when the drop moves nothing.
    let perform: (String) -> Bool
    let locationChanged: (CGFloat) -> Void
    let ended: () -> Void
    let targeted: (Bool) -> Void
    /// The dropped song's id and the drag image's frame at release, in the host.
    let land: (String, CGRect?) -> Void
    let refreshedContent: () -> Content
    var boardScroll: ArchiveBoardScrollController? = nil

    func makeNSView(context: Context) -> ArchiveBoardDropHostingView<Content> {
        let view = ArchiveBoardDropHostingView(rootView: content)
        configure(view)
        return view
    }

    func updateNSView(_ view: ArchiveBoardDropHostingView<Content>, context: Context) {
        update(view)
    }

    func update(_ view: ArchiveBoardDropHostingView<Content>) {
        if view.renderedKey != renderKey { view.rootView = content }
        configure(view)
    }

    private func configure(_ view: ArchiveBoardDropHostingView<Content>) {
        if view.renderedKey?.isBoardVisible == true, !renderKey.isBoardVisible {
            view.resetColumnScrollPosition()
        }
        view.renderedKey = renderKey
        view.isHidden = !renderKey.isBoardVisible
        view.accepts = accepts
        view.perform = perform
        view.locationChanged = locationChanged
        view.ended = ended
        view.targeted = targeted
        view.land = land
        view.refreshedContent = refreshedContent
        boardScroll?.register(view, columnID: renderKey.column.id, isDropTargeted: renderKey.isTargeted)
    }
}

final class ArchiveBoardDropHostingView<Content: View>: NSHostingView<Content>, ArchiveBoardColumnFrameSpace {
    var renderedKey: ArchiveBoardColumnRenderKey?
    var accepts: (String) -> Bool = { _ in false }
    var perform: (String) -> Bool = { _ in false }
    var locationChanged: (CGFloat) -> Void = { _ in }
    var ended: () -> Void = {}
    var targeted: (Bool) -> Void = { _ in }
    var land: (String, CGRect?) -> Void = { _, _ in }
    var refreshedContent: (() -> Content)?
    /// NMH-141: tracks whether this view pushed the not-allowed cursor for a
    /// rejected drag, so the push/pop stays balanced per view.
    private(set) var isShowingNotAllowedCursor = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        isFlipped = true
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// A drag can outlive this view (SwiftUI recreates the representable, the
    /// column collapses): AppKit then never sends draggingExited/Ended, so
    /// balance the cursor stack here instead of leaving the not-allowed
    /// pointer stuck process-wide.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { popNotAllowedCursorIfNeeded() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func acceptedID(_ sender: any NSDraggingInfo) -> String? {
        guard let id = sender.draggingPasteboard.string(forType: .string), accepts(id) else { return nil }
        return id
    }

    /// Match the former board remount's scroll reset before hiding the native
    /// subtree; hidden hosting roots may defer their SwiftUI body updates.
    func resetColumnScrollPosition() {
        func reset(_ view: NSView) {
            if let scroll = view as? NSScrollView {
                var top = scroll.contentView.bounds
                top.origin = .zero
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(top).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            } else {
                view.subviews.forEach(reset)
            }
        }
        reset(self)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard acceptedID(sender) != nil else {
            targeted(false)
            ended()
            // NMH-141 (TRACK-39): show the not-allowed pointer on rejected drags
            // (archive-only projection / busy vault). Do not change accept rules.
            pushNotAllowedCursor()
            return []
        }
        popNotAllowedCursorIfNeeded()
        targeted(true)
        locationChanged(convert(sender.draggingLocation, from: nil).x)
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { finish() }
    override func draggingEnded(_ sender: any NSDraggingInfo) { finish() }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { finish() }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    // `animatesToDestination` stays false: AppKit removes the drag image as
    // soon as the drop is accepted, and the board lands its own copy. AppKit's
    // slide ran beside the lane's row animation with no shared end, so it slid
    // onto a row that had already faded in.
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        acceptedID(sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { finish() }
        guard let id = acceptedID(sender) else { return false }
        let released = draggingFrame(of: id, in: sender)
        // A drop that moves nothing (the song's own lane) is refused, so AppKit
        // slides the image back to the row it came from.
        guard perform(id) else { return false }
        // Publish the destination content now, so the new row exists when the
        // landing looks for it.
        if let refreshedContent { rootView = refreshedContent() }
        layoutSubtreeIfNeeded()
        land(id, released)
        return true
    }

    /// Where the drag image is at release, in this view.
    private func draggingFrame(of id: String, in sender: any NSDraggingInfo) -> CGRect? {
        var frame: CGRect?
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSString.self], searchOptions: [:]) { item, _, stop in
            guard item.item as? String == id else { return }
            frame = item.draggingFrame
            stop.pointee = true
        }
        return frame.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func finish() {
        popNotAllowedCursorIfNeeded()
        targeted(false)
        ended()
    }

    private func pushNotAllowedCursor() {
        guard !isShowingNotAllowedCursor else { return }
        isShowingNotAllowedCursor = true
        NSCursor.operationNotAllowed.push()
    }

    private func popNotAllowedCursorIfNeeded() {
        guard isShowingNotAllowedCursor else { return }
        isShowingNotAllowedCursor = false
        NSCursor.pop()
    }
}

/// The lane's native list, reached by the column's drop landing. Layout
/// measurements are not observable state: reading a frame must not
/// invalidate the board or make drag hover perform a new projection.
@MainActor
final class ArchiveBoardDropLayout {
    weak var nativeList: ArchiveBoardNativeSongListView?
    func frame(for id: String) -> CGRect? { nativeList?.cardFrame(for: id) }
}

/// Marks the native coordinate space used by the column's drop target.
protocol ArchiveBoardColumnFrameSpace: AnyObject {}

struct ArchiveBoardColumnRenderKey: Equatable {
    let column: ArchiveBoardColumn
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    var vaultActivity: [String: String] = [:]
    let isTargeted: Bool
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    var isCompact: Bool = false
    var isBoardVisible: Bool = true
}
