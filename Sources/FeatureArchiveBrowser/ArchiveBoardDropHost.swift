import AppCore
import AppKit
import SwiftUI

/// SwiftUI's DropDelegate cannot supply the drag manager's final image frame.
/// This boundary hosts one column and gives AppKit the actual laid-out card rect.
struct ArchiveBoardDropHost<Content: View>: NSViewRepresentable {
    let content: Content
    let renderKey: ArchiveBoardColumnRenderKey
    let accepts: (String) -> Bool
    let perform: (String) -> Void
    let locationChanged: (CGFloat) -> Void
    let ended: () -> Void
    let targeted: (Bool) -> Void
    let landingFrame: (String) -> CGRect?
    let refreshedContent: () -> Content
    let reduceMotion: Bool

    func makeNSView(context: Context) -> ArchiveBoardDropHostingView<Content> {
        let view = ArchiveBoardDropHostingView(rootView: content)
        configure(view)
        return view
    }

    func updateNSView(_ view: ArchiveBoardDropHostingView<Content>, context: Context) {
        if view.renderedKey != renderKey { view.rootView = content }
        configure(view)
    }

    private func configure(_ view: ArchiveBoardDropHostingView<Content>) {
        view.renderedKey = renderKey
        view.accepts = accepts
        view.perform = perform
        view.locationChanged = locationChanged
        view.ended = ended
        view.targeted = targeted
        view.landingFrame = landingFrame
        view.refreshedContent = refreshedContent
        view.reduceMotion = reduceMotion
    }
}

final class ArchiveBoardDropHostingView<Content: View>: NSHostingView<Content> {
    var renderedKey: ArchiveBoardColumnRenderKey?
    var accepts: (String) -> Bool = { _ in false }
    var perform: (String) -> Void = { _ in }
    var locationChanged: (CGFloat) -> Void = { _ in }
    var ended: () -> Void = {}
    var targeted: (Bool) -> Void = { _ in }
    var landingFrame: (String) -> CGRect? = { _ in nil }
    var refreshedContent: (() -> Content)?
    var reduceMotion = false
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

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard acceptedID(sender) != nil else { return false }
        // AppKit reads this before calling performDragOperation.
        sender.animatesToDestination = !reduceMotion
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { finish() }
        guard let id = acceptedID(sender) else { return false }
        perform(id)
        // Publish the destination content now so its final layout is available
        // before returning the accepted drop to AppKit.
        if let refreshedContent { rootView = refreshedContent() }
        layoutSubtreeIfNeeded()
        if let frame = landingFrame(id), frame.intersects(bounds) {
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSString.self], searchOptions: [:]) { item, _, _ in
                guard item.item as? String == id else { return }
                item.draggingFrame = frame
            }
        }
        return true
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

/// Layout measurements are not observable state: recording a frame must not
/// invalidate the board or make drag hover perform a new projection.
@MainActor
final class ArchiveBoardDropLayout {
    var frames: [String: CGRect] = [:]
}

struct ArchiveBoardCardFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ArchiveBoardColumnRenderKey: Equatable {
    let column: ArchiveBoardColumn
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    var vaultActivity: [String: String] = [:]
    let isTargeted: Bool
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    var isCompact: Bool = false
}
