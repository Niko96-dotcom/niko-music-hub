import AppKit
import SwiftUI

/// AppKit moves the eight existing column hosts as one document. There is no
/// additional SwiftUI hosting root and no offset publication through the board.
struct ArchiveBoardHorizontalScroll: NSViewRepresentable {
    let controller: ArchiveBoardScrollController
    let presentation: ArchiveBoardLanesPresentation
    let viewModel: ArchiveBrowserViewModel
    let onInteract: () -> Void
    let locationChanged: (String, CGFloat) -> Void
    let ended: () -> Void

    func makeNSView(context: Context) -> ArchiveBoardHorizontalScrollView {
        let view = ArchiveBoardHorizontalScrollView(controller: controller)
        view.apply(self)
        return view
    }

    func updateNSView(_ view: ArchiveBoardHorizontalScrollView, context: Context) {
        withTransaction(context.transaction) { view.apply(self) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArchiveBoardHorizontalScrollView, context: Context) -> CGSize? {
        // This is a viewport, not a content-sized control. Do not ask AppKit to
        // fit the document (and all its hosted card rows) for min/ideal/max probes.
        let width = proposal.width ?? nsView.bounds.width
        let height = proposal.height ?? nsView.bounds.height
        return CGSize(width: width.isFinite ? width : nsView.bounds.width,
                      height: height.isFinite ? height : nsView.bounds.height)
    }
}

@MainActor
protocol ArchiveBoardDocumentSizing: AnyObject {
    func setDocumentWidth(_ width: CGFloat)
}

final class ArchiveBoardHorizontalScrollView: NSScrollView, ArchiveBoardDocumentSizing {
    private let boardDocument = ArchiveBoardLaneDocument()
    private var controller: ArchiveBoardScrollController
    private var lanes: [String: ArchiveBoardNativeColumn] = [:]
    private var orderedIDs: [String] = []
    private var naturalWidth: CGFloat = 0
    private var positioned = false
    private var isRightToLeft = false

    init(controller: ArchiveBoardScrollController) {
        self.controller = controller
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        focusRingType = .none
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        documentView = boardDocument
        controller.scrollView = self
        NotificationCenter.default.addObserver(self, selector: #selector(liveScroll(_:)),
                                               name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(liveScroll(_:)),
                                               name: NSScrollView.didLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clipMoved(_:)),
                                               name: NSView.boundsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var acceptsFirstResponder: Bool { false }

    func apply(_ input: ArchiveBoardHorizontalScroll) {
        if controller !== input.controller {
            controller.activity.removeAllHover()
            controller.scrollView = nil
            controller = input.controller
            controller.scrollView = self
        }
        let key = input.presentation
        if !key.state.isBoardVisible { controller.activity.removeAllHover() }
        controller.onInteract = input.onInteract
        controller.isRightToLeft = key.layoutDirection == .rightToLeft
        if controller.isRightToLeft != isRightToLeft {
            isRightToLeft = controller.isRightToLeft
            positioned = false
            needsLayout = true
        }
        let nextIDs = key.columns.map(\.id)
        if nextIDs != orderedIDs {
            for id in orderedIDs where !nextIDs.contains(id) { lanes.removeValue(forKey: id)?.view.removeFromSuperview() }
            orderedIDs = nextIDs
            needsLayout = true
        }
        controller.configureDocument(columnIDs: nextIDs, compactIDs: key.compactColumnIDs)
        for column in key.columns {
            let value = ArchiveBoardColumnInput(
                column: column, state: key.state, viewModel: input.viewModel,
                compactWhenEmpty: key.compactColumnIDs.contains(column.id), colorScheme: key.colorScheme,
                reduceMotion: key.reduceMotion, boardScroll: controller,
                locationChanged: input.locationChanged, ended: input.ended
            )
            if let lane = lanes[column.id] { lane.apply(value) }
            else {
                let lane = ArchiveBoardNativeColumn(input: value)
                lanes[column.id] = lane
                boardDocument.addSubview(lane.view)
            }
        }
    }

    func setDocumentWidth(_ width: CGFloat) {
        guard naturalWidth != width else { return }
        naturalWidth = width
        needsLayout = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { controller.activity.removeAllHover() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: max(contentView.bounds.width, naturalWidth), height: contentView.bounds.height)
        if boardDocument.frame.size != size {
            boardDocument.setFrameSize(size)
            let constrained = contentView.constrainBoundsRect(contentView.bounds)
            if contentView.bounds.origin != constrained.origin { contentView.scroll(to: constrained.origin) }
            reflectScrolledClipView(contentView)
        }
        var x: CGFloat = isRightToLeft ? size.width : 0
        for id in orderedIDs {
            guard let lane = lanes[id] else { continue }
            if isRightToLeft { x -= lane.width }
            let frame = NSRect(x: x, y: 2, width: lane.width, height: max(0, size.height - 4))
            if lane.view.frame != frame { lane.view.frame = frame }
            x += isRightToLeft ? -ArchiveBoardLaneLayout.spacing : lane.width + ArchiveBoardLaneLayout.spacing
        }
        if !positioned, size.width > 0, size.height > 0 {
            positioned = true
            if isRightToLeft {
                var trailing = contentView.bounds
                trailing.origin.x = size.width - trailing.width
                contentView.scroll(to: contentView.constrainBoundsRect(trailing).origin)
                reflectScrolledClipView(contentView)
            }
        }
    }

    @objc private func liveScroll(_ notification: Notification) {
        guard let scroll = notification.object as? NSScrollView, scroll.isDescendant(of: self) else { return }
        controller.activity.recordActivity()
    }

    @objc private func clipMoved(_ notification: Notification) {
        guard let clip = notification.object as? NSClipView, clip.isDescendant(of: self) else { return }
        controller.activity.recordActivity()
    }
}

private final class ArchiveBoardLaneDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Measurements are read only during a drag, in the native clip coordinate
/// space. No geometry preferences publish the offset through every lane.
@MainActor
final class ArchiveBoardScrollController {
    let activity = ArchiveBoardScrollActivity()
    var onInteract: () -> Void = {}
    var isRightToLeft = false
    weak var scrollView: NSScrollView?
    private let columns = NSMapTable<NSString, NSView>.strongToWeakObjects()
    private var horizontalGesture = false
    private var columnIDs: [String] = []
    private var compactIDs: Set<String> = []
    private var expandedIDs: Set<String> = []

    var viewportWidth: CGFloat { scrollView?.contentView.bounds.width ?? 0 }

    func register(_ view: NSView, columnID: String, isDropTargeted: Bool = false) {
        columns.setObject(view, forKey: columnID as NSString)
        if isDropTargeted { expandedIDs.insert(columnID) }
        else { expandedIDs.remove(columnID) }
        updateDocumentWidth()
    }

    func configureDocument(columnIDs: [String], compactIDs: Set<String>) {
        self.columnIDs = columnIDs
        self.compactIDs = compactIDs
        expandedIDs.formIntersection(columnIDs)
        updateDocumentWidth()
    }

    private func updateDocumentWidth() {
        let width = ArchiveBoardLaneLayout.documentWidth(columnIDs: columnIDs, compactIDs: compactIDs, expandedIDs: expandedIDs)
        (scrollView as? any ArchiveBoardDocumentSizing)?.setDocumentWidth(width)
    }

    /// A lane must not consume lateral deltas or rubber-band independently.
    /// Share ownership across lanes, including the zero-delta phase endings.
    func routeHorizontalWheel(_ event: NSEvent) -> Bool {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { horizontalGesture = false }
        let unphased = event.phase.isEmpty && event.momentumPhase.isEmpty
        let dominant = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        let horizontal = unphased ? dominant : (horizontalGesture || dominant)
        if !unphased && horizontal { horizontalGesture = true }
        if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { horizontalGesture = false }
        guard horizontal, let scrollView else { return false }
        activity.recordWheel(event)
        scrollView.scrollWheel(with: event)
        return true
    }

    func columnOrigins() -> [String: CGFloat] {
        guard let clip = scrollView?.contentView else { return [:] }
        var origins: [String: CGFloat] = [:]
        for key in columns.keyEnumerator() {
            guard let key = key as? NSString, let view = columns.object(forKey: key) else { continue }
            let frame = view.convert(view.bounds, to: clip).offsetBy(dx: -clip.bounds.minX, dy: 0)
            origins[key as String] = isRightToLeft ? clip.bounds.width - frame.maxX : frame.minX
        }
        return origins
    }

    func scroll(to columnID: String, animated: Bool) {
        guard let scrollView, let view = columns.object(forKey: columnID as NSString),
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        var target = clip.bounds
        let frame = view.convert(view.bounds, to: document)
        target.origin.x = isRightToLeft ? frame.maxX - clip.bounds.width : frame.minX
        let origin = clip.constrainBoundsRect(target).origin
        activity.recordActivity()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? ArchiveBoardMotion.duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    func pointerX(columnID: String, localX: CGFloat) -> CGFloat? {
        guard let clip = scrollView?.contentView, let view = columns.object(forKey: columnID as NSString) else { return nil }
        let x = view.convert(NSPoint(x: localX, y: 0), to: clip).x - clip.bounds.minX
        return isRightToLeft ? clip.bounds.width - x : x
    }
}
