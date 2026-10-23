import AppCore
import AppKit
import Combine
import Darwin
import Foundation
import NikoMusicCore
import ObjectiveC
import QuartzCore
import SwiftUI
@testable import FeatureArchiveBrowser

// In-process launch and interaction benchmark for a large archive (the bake-off 10k archive).
//
//   script/benchmark_archive_startup.sh launch --archive <CubaseArchive> --database <archive-index.sqlite> \
//       [--scenarios launch,open,scroll,search,detail,analytics] [--timeout SECONDS]
//
// One process = one launch. It builds the archive view model the way AppComposition does (settings
// with one scan root, the real SQLite stores on a COPY of the database, the cached index, then the
// background rescan), mounts the real ArchiveBrowserView in an AppKit window, and records:
//   * the launch timeline (model init, cached songs published, first filtered list, scan finished),
//   * main-run-loop stalls (2 ms heartbeat) per phase,
//   * then, once the scan is done, timed interactions: opening the board and the list, deep scrolling,
//     searching old and recent material, opening an old song's detail page, opening analytics.
// Interaction times are model mutation + NSHostingView layout + display + CATransaction flush. They
// are not GPU frame times. One JSON object goes to stdout.

private struct SilentDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

private struct NoFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func chooseDirectory(prompt: String) -> URL? { nil }
    func chooseExecutable(prompt: String) -> URL? { nil }
    func chooseAudioFile(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}

private func threadCPUTime() -> Double {
    var value = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value)
    return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
}

private func processCPUTime() -> Double {
    var value = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value)
    return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
}

private func footprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

@MainActor
private final class Heartbeat: NSObject {
    var last = CACurrentMediaTime()
    var gaps: [(at: Double, gap: Double)] = []
    @objc func tick() {
        let now = CACurrentMediaTime()
        gaps.append((now, (now - last) * 1000))
        last = now
    }

    /// Longest gap, total time lost in gaps above 50 ms, and how many gaps exceeded 50 and 100 ms.
    func summary(from start: Double, to end: Double) -> [String: Double] {
        let window = gaps.filter { $0.at >= start && $0.at <= end }.map(\.gap)
        let stalls = window.filter { $0 > 50 }
        return [
            "max_gap_ms": window.max() ?? 0,
            "stalled_ms": stalls.reduce(0) { $0 + ($1 - 2) },
            "gaps_over_50ms": Double(stalls.count),
            "gaps_over_100ms": Double(window.filter { $0 > 100 }.count)
        ]
    }

    /// Every gap above 50 ms as (milliseconds since `origin`, gap), so a stall can be tied to a timeline event.
    func stallEvents(since origin: Double) -> [[String: Double]] {
        gaps.filter { $0.gap > 50 }.map { ["at_ms": ($0.at - origin) * 1000, "gap_ms": $0.gap] }
    }
}

@MainActor
private final class ScrollTarget: ObservableObject {
    @Published var id: String?
}

private struct BenchmarkRoot: View {
    let context: ToolContext
    let model: ArchiveBrowserViewModel
    var body: some View {
        ArchiveBrowserView(context: context, viewModel: model)
    }
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

@main
@MainActor
struct ArchiveLaunchBenchmark {
    static func main() throws {
        // The app's main thread runs at user-interactive QoS; a shell-launched process starts at utility,
        // which the scheduler may place on efficiency cores. Match the app.
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        var archivePath: String?
        var databasePath: String?
        var timeout = 300.0
        var runsOverride: Int?
        var scenarios: Set<String> = ["launch", "open", "scroll", "wheel", "search", "detail", "browse", "stage", "apply", "analytics"]
        var arguments = Array(CommandLine.arguments.dropFirst())[...]
        if arguments.first == "launch" { arguments.removeFirst() }
        while let argument = arguments.popFirst() {
            switch argument {
            case "--archive": archivePath = arguments.popFirst()
            case "--database": databasePath = arguments.popFirst()
            case "--timeout": timeout = Double(arguments.popFirst() ?? "") ?? timeout
            case "--runs": runsOverride = Int(arguments.popFirst() ?? "")
            case "--scenarios": scenarios = Set((arguments.popFirst() ?? "").split(separator: ",").map(String.init))
            default:
                FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
                exit(64)
            }
        }
        guard let archivePath, let databasePath else {
            FileHandle.standardError.write(Data("usage: archive-launch --archive <dir> --database <sqlite> [--scenarios a,b] [--timeout s]\n".utf8))
            exit(64)
        }

        if scenarios.contains("horizontal") {
            // Direct, synchronous injection has no WindowServer event stream for
            // AppKit's concurrent gesture tracker to consume. Disable that tracker
            // in this harness only, equally for both comparison binaries.
            let selector = NSSelectorFromString("isCompatibleWithResponsiveScrolling")
            let method = class_getClassMethod(NSScrollView.self, selector)!
            let implementation: @convention(block) (AnyObject) -> Bool = { _ in false }
            class_replaceMethod(object_getClass(NSScrollView.self)!, selector,
                                imp_implementationWithBlock(implementation), method_getTypeEncoding(method))
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("NMH-Launch-Bench-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let databaseURL = work.appendingPathComponent("archive-index.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databasePath + suffix)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: URL(fileURLWithPath: databaseURL.path + suffix))
            }
        }
        let suite = "NMH.Launch.Performance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let suitePlist = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: suitePlist)
            try? fm.removeItem(at: work)
        }
        let archive = URL(fileURLWithPath: archivePath, isDirectory: true).standardizedFileURL
        let settingsStore = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        try settingsStore.updateSettings {
            $0.musicRoots = [StoredMusicRoot(role: .scanOnly, displayName: "Synthetic Archive", pathFallback: archive.path)]
            $0.archiveOnboardingCompleted = true
            $0.outputFolder = StoredFolderLocation(url: work.appendingPathComponent("Output"))
        }
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: settingsStore,
            preferences: UserDefaultsPreferenceStore(userDefaults: defaults),
            outputInboxStore: JSONOutputInboxStore(storageURL: work.appendingPathComponent("inbox.json")),
            jobRunner: JobRunner(),
            fileActions: NoFileActions(),
            diagnostics: SilentDiagnostics()
        )
        let runtime = MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.dryRunOpenKey: "1"])

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        if let appearance = ProcessInfo.processInfo.environment["NMH_SCROLL_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        let heartbeat = Heartbeat()
        let timer = Timer(timeInterval: 0.002, target: heartbeat, selector: #selector(Heartbeat.tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)

        let launchStart = CACurrentMediaTime()
        let launchCPU = processCPUTime()
        let mainCPUStart = threadCPUTime()
        var events: [(name: String, at: Double)] = []
        func mark(_ name: String) { events.append((name, (CACurrentMediaTime() - launchStart) * 1000)) }

        // Same store wiring as AppComposition.
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let model = ArchiveBrowserViewModel(
            context: context,
            archiveIndexStore: try SQLiteArchiveIndexStore(database: database),
            songMetadataStore: try SQLiteSongUserMetadataStore(database: database),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            collaboratorStore: try SQLiteCollaboratorStore(database: database),
            runtime: runtime
        )
        mark("model_init_done")
        let mainCPUAfterInit = threadCPUTime()

        var cancellables = Set<AnyCancellable>()
        var scanStarted = false
        var scanFinished = false
        // The catalog has no publisher of its own (it is written through `applyCatalogEdit`); read
        // `songs` one run-loop turn after a change is announced. Builds against older commits too,
        // so an A/B run measures both sides the same way.
        model.objectWillChange.sink { _ in
            RunLoop.main.perform {
                if !model.songs.isEmpty, !events.contains(where: { $0.name == "songs_published" }) { mark("songs_published") }
            }
        }.store(in: &cancellables)
        model.$filteredSongs.dropFirst().sink { songs in
            if !songs.isEmpty, !events.contains(where: { $0.name == "filtered_songs_published" }) { mark("filtered_songs_published") }
        }.store(in: &cancellables)
        model.$isScanning.sink { scanning in
            if scanning, !scanStarted { scanStarted = true; mark("scan_started") }
            if !scanning, scanStarted, !scanFinished { scanFinished = true; mark("scan_finished") }
        }.store(in: &cancellables)

        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Niko Music Hub — Launch Benchmark"
        let host = NSHostingView(rootView: BenchmarkRoot(context: context, model: model))
        host.sizingOptions = []
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        mark("window_shown")

        func settle(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func render() {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
        }

        // Launch: wait for the background rescan to finish, driving the run loop in 5 ms steps.
        let deadline = launchStart + timeout
        while !scanFinished && CACurrentMediaTime() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        let scanFinishedAt = CACurrentMediaTime()
        settle(1.0)
        render()
        let launchEnd = CACurrentMediaTime()
        let eventTimes = Dictionary(events.map { ($0.name, $0.at) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Any] = [
            "songs": model.songs.count,
            "filtered": model.filteredSongs.count,
            "scan_finished": scanFinished,
            "timeline_ms": eventTimes,
            "model_init_main_cpu_ms": (mainCPUAfterInit - mainCPUStart) * 1000,
            "launch_main_cpu_ms": (threadCPUTime() - mainCPUStart) * 1000,
            "launch_process_cpu_ms": (processCPUTime() - launchCPU) * 1000,
            "launch_wall_ms": (scanFinishedAt - launchStart) * 1000,
            "footprint_mib_after_launch": footprintMiB(),
            "main_stalls_launch": heartbeat.summary(from: launchStart, to: launchEnd)
        ]
        result["stall_events_launch"] = heartbeat.stallEvents(since: launchStart)
        if let published = eventTimes["songs_published"] {
            let publishedAt = launchStart + published / 1000
            result["main_stalls_after_cache_published"] = heartbeat.summary(from: publishedAt, to: scanFinishedAt)
        }

        // Interactions.
        var rows: [[String: Any]] = []
        func measure(_ name: String, runs requestedRuns: Int = 7, warmups: Int = 1,
                     prepare: (Int) -> Void = { _ in }, operation: (Int) -> Void) {
            let runs = runsOverride ?? requestedRuns
            FileHandle.standardError.write(Data("measuring \(name)\n".utf8))
            var wall: [Double] = []
            var cpu: [Double] = []
            var stall: [Double] = []
            var first = 0.0
            for index in 0..<(runs + warmups) {
                prepare(index)
                settle()
                autoreleasepool {
                    let start = CACurrentMediaTime()
                    let cpuStart = threadCPUTime()
                    operation(index)
                    let elapsed = (CACurrentMediaTime() - start) * 1000
                    let cpuElapsed = (threadCPUTime() - cpuStart) * 1000
                    if index == 0 { first = elapsed }
                    if index >= warmups { wall.append(elapsed); cpu.append(cpuElapsed) }
                    stall.append(elapsed)
                }
            }
            let sorted = wall.sorted()
            rows.append(["scenario": name, "first_ms": first, "median_ms": median(wall), "min_ms": sorted.first ?? 0,
                         "max_ms": sorted.last ?? 0, "main_cpu_median_ms": median(cpu), "samples_ms": wall])
            FileHandle.standardError.write(Data(String(format: "%-34@ median %9.2f ms (min %9.2f max %9.2f) first %9.2f\n",
                name as NSString, median(wall), sorted.first ?? 0, sorted.last ?? 0, first).utf8))
        }

        func scrollViews() -> [NSScrollView] {
            var found: [NSScrollView] = []
            func walk(_ view: NSView) {
                if let scroll = view as? NSScrollView,
                   let document = scroll.documentView,
                   document.frame.height > scroll.contentView.bounds.height * 3 {
                    found.append(scroll)
                }
                view.subviews.forEach(walk)
            }
            walk(host)
            return found
        }
        func scroll(to fraction: Double) {
            for scroll in scrollViews() {
                guard let document = scroll.documentView else { continue }
                let travel = max(0, document.frame.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: travel * fraction))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        let ordered = model.filteredSongs
        // Default sort is recent-first, so the tail of the list is the oldest material.
        let oldest = ordered.last
        let newest = ordered.first
        func titleQuery(_ song: Song?) -> String {
            song?.displayTitle.split(separator: " ").prefix(2).joined(separator: " ") ?? "amber"
        }

        if scenarios.contains("horizontal") {
            model.viewMode = .board; model.selectedSong = nil; render(); settle(0.5)
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            guard let outer = descendants(host).compactMap({ $0 as? NSScrollView }).first(where: {
                ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 100
            }), let lane = scrollViews().first else { fatalError("Missing board scroll views") }
            let laneIDs = Set(scrollViews().map(ObjectIdentifier.init))
            let cardPoint = lane.convert(NSPoint(x: 80, y: 100), to: nil)
            var routing: [[String: Any]] = []
            for (name, dx, dy, phased, overCards) in [
                ("idle_control", 0, 0, false, false),
                ("outer_control", 12, 0, true, false),
                ("cards_horizontal", 12, 0, true, true),
                ("cards_diagonal", 12, 3, true, true),
                ("cards_wobble", 12, 0, true, true),
                ("outer_wobble", 12, 0, true, false),
                ("lane_direct", 12, 3, true, true),
                ("cards_mouse", 12, 0, false, true)
            ] {
                var times: [Double] = []
                var cpuTimes: [Double] = []
                var positions: [Double] = []
                var verticalDrift = 0.0
                for _ in 0..<(runsOverride ?? 3) {
                    outer.contentView.scroll(to: .zero); outer.reflectScrolledClipView(outer.contentView)
                    scroll(to: 0.5); render(); settle(0.2)
                    let initialY = Dictionary(uniqueKeysWithValues: scrollViews().map { (ObjectIdentifier($0), $0.contentView.bounds.minY) })
                    for direction in [-1, 1] {
                        for step in 0..<38 {
                            // Finger phase, finger end, then momentum including its terminal event.
                            let momentum = phased && step >= 25
                            let terminal = phased && (step == 24 || step == 37)
                            let factor = terminal ? 0 : (momentum ? 0.5 : 1.0)
                            let wobble = name.hasSuffix("wobble") && step < 2
                            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                             wheel1: Int32(Double((wobble ? 3 : dy) * direction) * factor),
                                             wheel2: Int32(Double((wobble ? 0 : dx) * direction) * factor), wheel3: 0)!
                            if phased {
                                cg.setIntegerValueField(.scrollWheelEventScrollPhase,
                                                        value: momentum ? 0 : (step == 0 ? 1 : (step == 24 ? 4 : 2)))
                                cg.setIntegerValueField(.scrollWheelEventMomentumPhase,
                                                        value: momentum ? (step == 25 ? 1 : (step == 37 ? 3 : 2)) : 0)
                            }
                            let screenPoint = window.convertPoint(toScreen: cardPoint)
                            cg.location = NSPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
                            let event = NSEvent(cgEvent: cg)!
                            let hit = host.hitTest(host.convert(cardPoint, from: nil))
                            let start = CACurrentMediaTime()
                            let cpuStart = threadCPUTime()
                            if name == "lane_direct" { lane.scrollWheel(with: event) }
                            else if overCards { (hit ?? lane).scrollWheel(with: event) }
                            else { outer.scrollWheel(with: event) }
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
                            settle(0.008)
                            host.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
                            times.append((CACurrentMediaTime() - start) * 1000)
                            cpuTimes.append((threadCPUTime() - cpuStart) * 1000)
                            positions.append(outer.contentView.bounds.minX)
                            verticalDrift = max(verticalDrift, scrollViews().map { abs($0.contentView.bounds.minY - (initialY[ObjectIdentifier($0)] ?? 0)) }.max() ?? 0)
                        }
                    }
                }
                let sorted = times.sorted()
                rows.append(["scenario": "horizontal_\(name)", "median_ms": median(times),
                             "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)], "max_ms": sorted.last ?? 0,
                             "samples_ms": times, "positions_x": positions, "max_x": positions.max() ?? 0,
                             "main_cpu_median_ms": median(cpuTimes), "main_cpu_samples_ms": cpuTimes,
                             "max_vertical_drift": verticalDrift])
                routing.append(["scenario": name, "event_x": dx, "event_y": dy,
                                "hit_class": String(describing: type(of: host.hitTest(host.convert(cardPoint, from: nil)) ?? host)),
                                "outer_class": String(describing: type(of: outer))])
                FileHandle.standardError.write(Data("horizontal \(name): median \(median(times)) ms, max x \(positions.max() ?? 0), y drift \(verticalDrift)\n".utf8))
            }
            result["horizontal_routing"] = routing
            result["native_lanes_retained"] = laneIDs == Set(scrollViews().map(ObjectIdentifier.init))
            result["realized_card_cells"] = descendants(host).filter { $0 is ArchiveBoardCardCell }.count
            if let artifacts = ProcessInfo.processInfo.environment["NMH_SCROLL_ARTIFACTS"] {
                outer.contentView.scroll(to: .zero); outer.reflectScrolledClipView(outer.contentView)
                scroll(to: 0); render(); settle(0.3)
                func rect(_ rect: NSRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height] }
                result["board_lane_frames"] = scrollViews().map { rect($0.convert($0.bounds, to: host)) }
                result["board_card_frames"] = descendants(host).compactMap { ($0 as? ArchiveBoardCardCell)?.cardFrame(in: host) }.map(rect)
                let url = URL(fileURLWithPath: artifacts, isDirectory: true)
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("board.png"))
                }
            }
        }
        if scenarios.contains("back") {
            model.viewMode = .board; render(); settle(0.3)
            measure("detail_to_board", prepare: { _ in
                if let newest { model.openSongDetail(newest); render(); settle(0.2) }
            }) { _ in model.viewMode = .board; render() }
        }
        if scenarios.contains("reach") {
            model.viewMode = .board; model.selectedSong = nil; render(); settle(0.3)
            guard let lane = scrollViews().max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
                  let table = lane.documentView as? NSTableView else { fatalError("Missing native lane") }
            let last = table.numberOfRows - 1
            var passed = 0
            var trials = 0
            measure("board_oldest_card_reachable", prepare: { _ in scroll(to: 0); render() }) { _ in
                trials += 1
                table.scrollRowToVisible(last)
                let deadline = CACurrentMediaTime() + 5
                while CACurrentMediaTime() < deadline {
                    render()
                    if let cell = table.view(atColumn: 0, row: last, makeIfNecessary: false) as? ArchiveBoardCardCell,
                       let frame = cell.cardFrame(in: lane.contentView),
                       lane.contentView.bounds.insetBy(dx: -1, dy: -1).contains(frame) {
                        passed += 1
                        break
                    }
                    settle(0.005)
                }
            }
            result["oldest_card_trials"] = trials
            result["oldest_card_passed"] = passed
        }

        if scenarios.contains("open") {
            model.viewMode = .list; render(); settle()
            measure("open_board", prepare: { _ in model.viewMode = .list; render() }) { _ in
                model.viewMode = .board; render()
            }
            measure("open_list", prepare: { _ in model.viewMode = .board; render() }) { _ in
                model.viewMode = .list; render()
            }
        }
        if scenarios.contains("wheel") {
            // Wheel-style scrolling in the tallest column (board) or the list: 40 steps of 120 pt, at the
            // top, halfway down and near the oldest songs. Per-step cost is model-free layout + display.
            func tallestScrollView() -> NSScrollView? {
                scrollViews().max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
            }
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.list, .board] {
                let label = mode == .list ? "list" : "board"
                model.viewMode = mode; model.selectedSong = nil; render(); settle(0.5)
                for (name, depth) in [("top", 0.0), ("middle", 0.5), ("oldest", 0.93)] {
                    guard let target = tallestScrollView(), let document = target.documentView else { continue }
                    let travel = max(0, document.frame.height - target.contentView.bounds.height)
                    target.contentView.scroll(to: NSPoint(x: 0, y: travel * depth))
                    target.reflectScrolledClipView(target.contentView)
                    render(); settle(0.3)
                    var steps: [Double] = []
                    for _ in 0..<40 {
                        guard let scrollView = tallestScrollView() else { break }
                        let y = scrollView.contentView.bounds.origin.y + 120
                        let start = CACurrentMediaTime()
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        render()
                        steps.append((CACurrentMediaTime() - start) * 1000)
                    }
                    let sorted = steps.sorted()
                    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                    rows.append(["scenario": "wheel_\(label)_\(name)", "median_ms": median(steps), "max_ms": sorted.last ?? 0,
                                 "p95_ms": p95, "min_ms": sorted.first ?? 0, "samples_ms": steps])
                    FileHandle.standardError.write(Data(String(format: "%-34@ median %9.2f ms (p95 %9.2f max %9.2f)\n",
                        "wheel_\(label)_\(name)" as NSString, median(steps), p95, sorted.last ?? 0).utf8))
                }
            }
        }
        if scenarios.contains("scroll") {
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.list, .board] {
                let label = mode == .list ? "list" : "board"
                model.viewMode = mode; model.selectedSong = nil; render(); settle(0.3)
                scroll(to: 0); render(); settle()
                measure("scroll_\(label)_jump_to_oldest", prepare: { _ in scroll(to: 0); render() }) { _ in
                    scroll(to: 1.0); render()
                }
                // A user dragging through the archive: ten steps from newest to oldest, each laid out.
                var stepTimes: [Double] = []
                scroll(to: 0); render(); settle(0.3)
                for step in 1...10 {
                    let start = CACurrentMediaTime()
                    scroll(to: Double(step) / 10); render()
                    stepTimes.append((CACurrentMediaTime() - start) * 1000)
                }
                rows.append(["scenario": "scroll_\(label)_ten_steps", "median_ms": median(stepTimes),
                             "max_ms": stepTimes.max() ?? 0, "min_ms": stepTimes.min() ?? 0, "samples_ms": stepTimes])
                FileHandle.standardError.write(Data(String(format: "%-34@ median %9.2f ms (max %9.2f)\n",
                    "scroll_\(label)_ten_steps" as NSString, median(stepTimes), stepTimes.max() ?? 0).utf8))
            }
        }
        if scenarios.contains("search") {
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.board, .list] {
                let label = mode == .board ? "board" : "list"
                model.viewMode = mode; model.selectedSong = nil
                model.setSearchQuery("", immediate: true); render(); settle(0.3)
                let queries: [(String, String)] = [("old", titleQuery(oldest)), ("recent", titleQuery(newest)), ("absent", "zzzz qqqq")]
                for (kind, query) in queries {
                    measure("search_\(label)_\(kind)", prepare: { _ in
                        model.setSearchQuery("", immediate: true); render()
                    }) { _ in
                        model.setSearchQuery(query, immediate: true); render()
                    }
                }
                model.setSearchQuery("", immediate: true); render(); settle()
            }
        }
        if scenarios.contains("detail") {
            model.viewMode = .board; model.setSearchQuery("", immediate: true); render(); settle(0.3)
            for (kind, song) in [("old", oldest), ("recent", newest)] {
                guard let song else { continue }
                measure("detail_open_\(kind)", prepare: { _ in
                    model.viewMode = .board; model.selectedSong = nil; render()
                }) { _ in
                    model.openSongDetail(song); render()
                }
            }
            model.viewMode = .board; model.selectedSong = nil; render(); settle()
        }
        if scenarios.contains("browse") {
            // Re-sorting and re-filtering the whole catalog: every sort mode and smart shelf, in the board and the list.
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.board, .list] {
                let label = mode == .board ? "board" : "list"
                model.viewMode = mode; model.selectedSong = nil
                model.setSortMode(.recentCPR); model.selectShelf(.allSongs); render(); settle(0.4)
                for sort in ArchiveBrowseSortMode.allCases where sort != .recentCPR {
                    measure("browse_\(label)_sort_\(sort.rawValue)", prepare: { _ in
                        model.setSortMode(.recentCPR); render()
                    }) { _ in
                        model.setSortMode(sort); render()
                    }
                }
                model.setSortMode(.recentCPR); render(); settle(0.3)
                for shelf in [ArchiveSmartShelf.recentlyBounced, .hasStems, .quietSongs] {
                    measure("browse_\(label)_shelf_\(shelf.rawValue)", prepare: { _ in
                        model.selectShelf(.allSongs); render()
                    }) { _ in
                        model.selectShelf(shelf); render()
                    }
                }
                model.selectShelf(.allSongs); render(); settle(0.3)
                measure("browse_\(label)_filter_has_stems", prepare: { _ in
                    model.mutateBrowseInputs { model.browseFilter = [] }; render()
                }) { _ in
                    model.toggleBrowseFilter(.hasStems); render()
                }
                model.mutateBrowseInputs { model.browseFilter = [] }; render()
            }
        }
        if scenarios.contains("eqcheck") {
            let first = model.filteredSongs
            let second = ArchiveBrowseProjection.project(model.browseState()).filteredSongs
            measure("eq_filtered_vs_reprojected", runs: 5) { _ in _ = (first == second) }
            let columnsA = ArchiveBoardProjection.columns(from: first)
            let columnsB = ArchiveBoardProjection.columns(from: first)
            measure("eq_columns_reprojected", runs: 5) { _ in _ = (columnsA == columnsB) }
            let live = model.songs
            measure("eq_songs_vs_scanned", runs: 5) { _ in _ = (live == model.scannedSongs) }
            func sharedPreviews(_ x: [Song], _ y: [Song]) -> Int {
                var shared = 0
                for (left, right) in zip(x, y) where left.id == right.id {
                    let same = left.previewCandidates.withUnsafeBufferPointer { l in
                        right.previewCandidates.withUnsafeBufferPointer { r in l.baseAddress == r.baseAddress }
                    }
                    if same { shared += 1 }
                }
                return shared
            }
            let sortedLive = ArchiveBrowseSortMode.sort(live, mode: .recentCPR)
            FileHandle.standardError.write(Data("shared preview storage: filtered/reprojected \(sharedPreviews(first, second)) of \(first.count); songs/sorted \(sharedPreviews(live.sorted { $0.id < $1.id }, sortedLive.sorted { $0.id < $1.id })) ; songs/scanned \(sharedPreviews(live, model.scannedSongs))\n".utf8))
        }
        if scenarios.contains("stage") {
            // Moving a card: change the workflow status of an old and a recent song the way the board's
            // drop and the context menu do (SQLite write, catalog replace, browse re-projection, layout).
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.board, .list] {
                let label = mode == .board ? "board" : "list"
                model.viewMode = mode; model.selectedSong = nil
                model.setSortMode(.recentCPR); model.selectShelf(.allSongs); render(); settle(0.5)
                for (kind, target) in [("old", oldest), ("recent", newest)] {
                    guard let target else { continue }
                    measure("stage_change_\(label)_\(kind)", prepare: { _ in settle(0.6) }) { index in
                        guard let live = model.songs.first(where: { $0.id == target.id }) else { return }
                        model.updateWorkflowStatus(for: live, status: index % 2 == 0 ? .songstarterBeat : .song)
                        render()
                    }
                }
            }
        }
        if scenarios.contains("apply") {
            // A rescan that finds the archive unchanged (the usual launch): merge the scan result with the
            // stored metadata, then publish it to the view model on the main actor.
            let scanned = ScanResult(songs: model.scannedSongs, globalWarnings: [], skippedEntries: [])
            measure("apply_merge_scan_result", runs: 5) { _ in
                _ = model.catalog.applyFullScanResult(
                    result: scanned, roots: model.roots, collaborators: model.collaborators, scannedAt: Date())
            }
            let update = model.catalog.applyFullScanResult(
                result: scanned, roots: model.roots, collaborators: model.collaborators, scannedAt: Date())
            model.viewMode = .board; render(); settle(0.3)
            measure("apply_catalog_update_board", runs: 5, prepare: { _ in settle(0.4) }) { _ in
                model.applyCatalogScanUpdate(update, roots: model.roots); render()
            }
            model.viewMode = .list; render(); settle(0.3)
            measure("apply_catalog_update_list", runs: 5, prepare: { _ in settle(0.4) }) { _ in
                model.applyCatalogScanUpdate(update, roots: model.roots); render()
            }
            model.viewMode = .board; render()
        }
        if scenarios.contains("analytics") {
            measure("analytics_open", prepare: { _ in model.viewMode = .board; render() }) { _ in
                model.showAnalytics(); render()
            }
            model.viewMode = .board; render()
        }

        result["interactions"] = rows
        result["footprint_mib_end"] = footprintMiB()
        timer.invalidate()
        window.close()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
}
