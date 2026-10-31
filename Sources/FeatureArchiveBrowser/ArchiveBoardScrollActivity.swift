import AppKit
import SwiftUI

enum ArchiveBoardMotion {
    /// Lane jumps: quick.
    static let duration = 0.16
    static let animation = Animation.easeOut(duration: duration)
    static let hover = Animation.easeOut(duration: 0.10)
    /// A song changing lanes. Both lanes' rows make room and close up, and the
    /// moved row fades in, at this slow pace and curve, so the board moves as
    /// one calm motion: a gentle start and a long, soft stop.
    static let move = 0.45
    static var moveCurve: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) }
    static let moveAnimation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: move)
}

enum ArchiveBoardHoverTarget: Hashable {
    case card(songID: String, laneID: String?)
    case play(songID: String, laneID: String?)

    var cardIdentity: (String, String?) {
        switch self { case .card(let id, let lane), .play(let id, let lane): return (id, lane) }
    }
}

/// Only the controls under the pointer participate. There are no per-card
/// subscriptions, tracking views, or offset publications through SwiftUI.
@MainActor
final class ArchiveBoardScrollActivity {
    private struct Hover {
        var displayed: Bool
        let change: (Bool) -> Void
    }
    private(set) var isScrolling = false
    private var hovered: [ArchiveBoardHoverTarget: Hover] = [:]
    private var lastEvent = Date.distantPast
    private var timer: Timer?
    private var liveScrolls: Set<ObjectIdentifier> = []

    func hover(_ target: ArchiveBoardHoverTarget, inside: Bool, at now: Date = Date(), change: @escaping (Bool) -> Void) {
        endIfIdle(at: now)
        if inside {
            for old in Array(hovered.keys) where old.cardIdentity != target.cardIdentity {
                if let previous = hovered.removeValue(forKey: old), previous.displayed { previous.change(false) }
            }
            let displayed = !isScrolling
            let previous = hovered.updateValue(Hover(displayed: displayed, change: change), forKey: target)?.displayed ?? false
            if previous != displayed { change(displayed) }
        } else if let previous = hovered.removeValue(forKey: target), previous.displayed {
            previous.change(false)
        }
    }

    static func updateHover(_ inside: Bool, target: ArchiveBoardHoverTarget?,
                            isHovered: Binding<Bool>, activity: ArchiveBoardScrollActivity?) {
        if let activity, let target {
            activity.hover(target, inside: inside) {
                if isHovered.wrappedValue != $0 { isHovered.wrappedValue = $0 }
            }
            if !inside, isHovered.wrappedValue { isHovered.wrappedValue = false }
        } else if isHovered.wrappedValue != inside {
            isHovered.wrappedValue = inside
        }
    }

    func removeAllHover() { hovered.removeAll() }

    func removeHover(songID: String, laneID: String?) {
        guard !hovered.isEmpty else { return }
        hovered = hovered.filter { target, _ in
            switch target {
            case .card(let id, let lane), .play(let id, let lane): return id != songID || lane != laneID
            }
        }
    }

    func beginLiveScroll(source: ObjectIdentifier) {
        liveScrolls.insert(source)
        recordActivity()
    }

    func endLiveScroll(source: ObjectIdentifier) {
        guard liveScrolls.remove(source) != nil else { return }
        if liveScrolls.isEmpty { endScrolling() }
    }

    /// A real pointer move is immediate intent to hover after unphased wheel
    /// scrolling. Live trackpad/momentum notifications still take precedence.
    func pointerMoved() {
        if liveScrolls.isEmpty { endScrolling() }
    }

    func recordWheel(_ event: NSEvent) {
        guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
        recordActivity()
    }

    func recordActivity(at now: Date = Date()) {
        lastEvent = now
        if !isScrolling {
            isScrolling = true
            refreshHover()
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.endIfIdle() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func endIfIdle(at now: Date = Date()) {
        guard now.timeIntervalSince(lastEvent) >= 0.16 else { return }
        endScrolling()
    }

    private func endScrolling() {
        timer?.invalidate()
        timer = nil
        if isScrolling {
            isScrolling = false
            refreshHover()
        }
    }

    private func refreshHover() {
        for target in Array(hovered.keys) {
            guard var hover = hovered[target], hover.displayed == isScrolling else { continue }
            hover.displayed = !isScrolling
            hovered[target] = hover
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { hover.change(hover.displayed) }
        }
    }

    isolated deinit { timer?.invalidate() }
}

/// One attached board viewport or lane owns this subscription. Exact senders
/// avoid callbacks for other tools, hosted controls, and ordinary view layout.
@MainActor
final class ArchiveBoardScrollObservation: NSObject {
    private let activity: ArchiveBoardScrollActivity

    init(scrollView: NSScrollView, activity: ArchiveBoardScrollActivity) {
        self.activity = activity
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(liveScrolled(_:)),
                           name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        center.addObserver(self, selector: #selector(liveScrolled(_:)),
                           name: NSScrollView.didLiveScrollNotification, object: scrollView)
        center.addObserver(self, selector: #selector(ended(_:)),
                           name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        center.addObserver(self, selector: #selector(scrolled(_:)),
                           name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func liveScrolled(_ notification: Notification) {
        activity.beginLiveScroll(source: ObjectIdentifier(self))
    }

    @objc private func ended(_ notification: Notification) {
        activity.endLiveScroll(source: ObjectIdentifier(self))
    }

    @objc private func scrolled(_ notification: Notification) {
        activity.recordActivity()
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        activity.endLiveScroll(source: ObjectIdentifier(self))
    }
}
