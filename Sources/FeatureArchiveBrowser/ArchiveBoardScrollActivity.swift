import AppKit
import SwiftUI

enum ArchiveBoardMotion {
    static let duration = 0.16
    static let animation = Animation.easeOut(duration: duration)
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

    func hover(_ target: ArchiveBoardHoverTarget, inside: Bool, change: @escaping (Bool) -> Void) {
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
