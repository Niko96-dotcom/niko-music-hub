import AppKit
import Foundation
import NikoMusicCore

/// Opt-in, in-process measurements of the real board. Requires the bakeoff's
/// isolated suite, dry-run opening and a request beside its synthetic archive.
/// No accessibility permission, global input events or real settings are used.
@MainActor
enum ArchivePerformanceProbe {
    private static var started = false
    private static var renderedMode: ArchiveBrowserViewModel.ArchiveViewMode?

    static func didRender(_ mode: ArchiveBrowserViewModel.ArchiveViewMode) {
        if started { renderedMode = mode }
    }

    static func runIfRequested(viewModel: ArchiveBrowserViewModel) async {
        guard !started, viewModel.runtime.dryRunOpen,
              viewModel.runtime.settingsSuiteName?.hasPrefix("NikoMusicHubBakeoff.") == true,
              let root = viewModel.roots.first,
              root.lastPathComponent == "CubaseArchive",
              root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "bakeoff-data"
        else { return }
        let request = root.deletingLastPathComponent().appendingPathComponent("perf-request.json")
        guard let data = try? Data(contentsOf: request),
              let config = try? JSONDecoder().decode(Configuration.self, from: data),
              (1...100).contains(config.runs), [1_000, 10_000].contains(config.songCount),
              (0...300).contains(config.settleSeconds ?? 60),
              config.label.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else { return }
        started = true
        var events: [[String: Any]] = []
        func record(_ name: String, _ values: [String: Any] = [:]) {
            var event = values
            event["scenario"] = name
            event["footprintMiB"] = footprintMiB()
            events.append(event)
            if let json = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
               let line = String(data: json, encoding: .utf8) {
                print("[archive-perf] \(line)")
            }
        }
        let began = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        record("waiting", [
            "sourceCommit": Bundle.main.object(forInfoDictionaryKey: "NMHSourceCommit") as? String ?? "unknown",
            "configuration": configuration,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ])
        guard await wait(timeout: 180, until: {
            viewModel.songs.count == config.songCount && !viewModel.isScanning && viewModel.scanDiagnostics != nil
        }) else {
            record("ready_timeout", ["songs": viewModel.songs.count])
            return
        }
        record("catalog_ready", ["ms": elapsed(began)])
        await viewModel.indexPersistTask?.value
        record("index_persisted", ["ms": elapsed(began)])
        await viewModel.intelligenceRefreshTask?.value
        record("intelligence_ready", ["ms": elapsed(began)])
        try? await Task.sleep(for: .seconds(2))
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else {
            record("no_window")
            return
        }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.orderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        record("ready", ["ms": (ProcessInfo.processInfo.systemUptime - began) * 1000,
                         "songs": viewModel.songs.count, "window": NSStringFromRect(window.frame)])
        let scenariosBegan = ProcessInfo.processInfo.systemUptime

        for run in 0..<config.runs {
            guard let lane = lanes(in: window).max(by: { $0.songCount < $1.songCount }),
                  let firstID = lane.firstSongID, let lastID = lane.lastSongID,
                  let scroll = descendants(lane.nativeView).compactMap({ $0 as? NSScrollView }).first,
                  let document = scroll.documentView else {
                record("no_lane")
                break
            }
            record("scroll_start", ["run": run, "count": lane.songCount,
                                    "documentHeight": document.frame.height,
                                    "topFrames": lane.topFrames,
                                    "lastLaidOut": lane.cardFrame(lastID) != nil])
            func oldestIsVisible() -> Bool {
                guard let frame = lane.cardFrame(lastID), frame.height > 0 else { return false }
                let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: lane.nativeView)
                // One point tolerates native pixel rounding; a card hidden
                // behind the lane header or clipped to a sliver never passes.
                return viewport.insetBy(dx: -1, dy: -1).contains(frame)
            }
            let wheelStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<60 {
                if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                       wheel1: -5000, wheel2: 0, wheel3: 0),
                   let wheel = NSEvent(cgEvent: event) {
                    scroll.scrollWheel(with: wheel)
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            let wheelReached = await wait(timeout: 5, until: oldestIsVisible)
            record("wheel_to_oldest", ["run": run, "ms": elapsed(wheelStart), "reached": wheelReached,
                                       "offset": scroll.contentView.bounds.minY,
                                       "documentHeight": document.frame.height,
                                       "oldestFrame": lane.cardFrame(lastID).map(NSStringFromRect) ?? "missing"])
            try? await Task.sleep(for: .milliseconds(750))
            record("wheel_settled", ["run": run,
                                      "offset": scroll.contentView.bounds.minY,
                                      "documentHeight": document.frame.height,
                                      "viewportHeight": scroll.contentView.bounds.height,
                                      "reached": oldestIsVisible(),
                                      "oldestFrame": lane.cardFrame(lastID).map(NSStringFromRect) ?? "missing"])
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            try? await Task.sleep(for: .milliseconds(200))
            let start = ProcessInfo.processInfo.systemUptime
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            let reached = await wait(timeout: 5, until: {
                window.contentView?.layoutSubtreeIfNeeded()
                return oldestIsVisible()
            })
            record("fling_to_oldest", ["run": run, "ms": elapsed(start), "reached": reached,
                                       "documentHeight": document.frame.height,
                                       "offset": scroll.contentView.bounds.minY,
                                       "oldestFrame": lane.cardFrame(lastID).map(NSStringFromRect) ?? "missing"])
            let detailID = run.isMultiple(of: 2) ? firstID : lastID
            if detailID == firstID {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                _ = await wait(timeout: 5, until: {
                    lane.cardFrame(firstID).map { $0.intersects(lane.nativeView.bounds) } ?? false
                })
            }
            guard let song = viewModel.songs.first(where: { $0.id == detailID }) else { break }
            let detailStart = ProcessInfo.processInfo.systemUptime
            renderedMode = nil
            viewModel.openSongDetail(song)
            let detailMounted = await wait(timeout: 5, until: { renderedMode == .boardDetail })
            window.contentView?.layoutSubtreeIfNeeded()
            record("open_detail", ["run": run, "ms": elapsed(detailStart), "mounted": detailMounted,
                                   "fromOldest": detailID == lastID,
                                   "hiddenLanes": lanes(in: window).filter { $0.nativeView.isHidden }.count])
            try? await Task.sleep(for: .milliseconds(500))
            let backStart = ProcessInfo.processInfo.systemUptime
            renderedMode = nil
            viewModel.viewMode = .board
            let mounted = await wait(timeout: 10, until: {
                window.contentView?.layoutSubtreeIfNeeded()
                return renderedMode == .board && lanes(in: window).contains {
                    !$0.nativeView.isHidden && $0.firstSongID == firstID
                        && ($0.cardFrame(firstID).map { $0.height > 0 } ?? false)
                }
            })
            record("detail_to_board", ["run": run, "ms": elapsed(backStart), "mounted": mounted])
            try? await Task.sleep(for: .milliseconds(500))
        }
        record("complete")
        let remaining = (config.settleSeconds ?? 60) - (ProcessInfo.processInfo.systemUptime - scenariosBegan)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        record("settled", ["secondsSinceReady": ProcessInfo.processInfo.systemUptime - scenariosBegan])
        do {
            let result = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            try result.write(to: request.deletingLastPathComponent().appendingPathComponent("perf-\(config.label).json"), options: .atomic)
        } catch { print("[archive-perf] result write failed: \(error)") }
    }

    private struct Configuration: Decodable {
        let label: String
        let runs: Int
        let songCount: Int
        var settleSeconds: Double?
    }

    private static func elapsed(_ start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    private static func wait(timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func lanes(in window: NSWindow) -> [any ArchivePerformanceLane] {
        window.contentView.map { descendants($0).compactMap { $0 as? any ArchivePerformanceLane } } ?? []
    }

    private static func footprintMiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

@MainActor
private protocol ArchivePerformanceLane {
    var nativeView: NSView { get }
    var songCount: Int { get }
    var firstSongID: String? { get }
    var lastSongID: String? { get }
    var topFrames: [String] { get }
    func cardFrame(_ id: String) -> CGRect?
}

extension ArchiveBoardDropHostingView: ArchivePerformanceLane {
    fileprivate var nativeView: NSView { self }
    fileprivate var songCount: Int { renderedKey?.column.songs.count ?? 0 }
    fileprivate var firstSongID: String? { renderedKey?.column.songs.first?.id }
    fileprivate var lastSongID: String? { renderedKey?.column.songs.last?.id }
    fileprivate var topFrames: [String] {
        renderedKey?.column.songs.prefix(6).map { song in
            landingFrame(song.id).map(NSStringFromRect) ?? "missing"
        } ?? []
    }
    fileprivate func cardFrame(_ id: String) -> CGRect? { landingFrame(id) }
}
