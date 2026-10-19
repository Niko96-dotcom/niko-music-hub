import AppCore
import AppKit
import Combine
import Darwin
import Foundation
import NikoMusicCore
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
        var archivePath: String?
        var databasePath: String?
        var timeout = 300.0
        var scenarios: Set<String> = ["launch", "open", "scroll", "search", "detail", "analytics"]
        var arguments = Array(CommandLine.arguments.dropFirst())[...]
        if arguments.first == "launch" { arguments.removeFirst() }
        while let argument = arguments.popFirst() {
            switch argument {
            case "--archive": archivePath = arguments.popFirst()
            case "--database": databasePath = arguments.popFirst()
            case "--timeout": timeout = Double(arguments.popFirst() ?? "") ?? timeout
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
        model.$songs.dropFirst().sink { songs in
            if !songs.isEmpty, !events.contains(where: { $0.name == "songs_published" }) { mark("songs_published") }
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
        func measure(_ name: String, runs: Int = 7, warmups: Int = 1,
                     prepare: (Int) -> Void = { _ in }, operation: (Int) -> Void) {
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

        if scenarios.contains("open") {
            model.viewMode = .list; render(); settle()
            measure("open_board", prepare: { _ in model.viewMode = .list; render() }) { _ in
                model.viewMode = .board; render()
            }
            measure("open_list", prepare: { _ in model.viewMode = .board; render() }) { _ in
                model.viewMode = .list; render()
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
