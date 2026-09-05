import AppKit
import AppCore
import NikoMusicCore
import SwiftUI
import QuartzCore
import Combine
import AVFoundation
import Darwin
@testable import FeatureArchiveBrowser

private func threadCPUTime() -> Double {
    var value = timespec()
    precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) == 0)
    return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
}

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

@MainActor
private final class BenchmarkWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApplication.shared.stop(nil) }
}

@MainActor
private final class ScrollController: ObservableObject {
    @Published var scrollTarget: String?
}
private struct BenchmarkRoot: View {
    let context: ToolContext
    let model: ArchiveBrowserViewModel
    @ObservedObject var controller: ScrollController
    var body: some View {
        ScrollViewReader { proxy in
            ArchiveBrowserView(context: context, viewModel: model)
                .onChange(of: controller.scrollTarget) { _, target in
                    if let target { proxy.scrollTo(target, anchor: .top) }
                }
        }
    }
}

@MainActor
private final class HeartbeatProbe: NSObject {
    var last = CACurrentMediaTime()
    var gaps = [Double]()
    var lastCPU = threadCPUTime()
    var cpuGaps = [Double]()
    @objc func tick() {
        let now = CACurrentMediaTime()
        gaps.append((now - last) * 1000)
        last = now
        let cpu = threadCPUTime()
        cpuGaps.append((cpu - lastCPU) * 1000)
        lastCPU = cpu
    }
}

@main
@MainActor
struct ArchiveUIBenchmark {
    static func main() throws {
        let detailOnly = CommandLine.arguments.contains("--detail-only")
        let stageOnly = CommandLine.arguments.contains("--stage-only")
        let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? (detailOnly || stageOnly ? 20 : 1000)
        precondition(count >= 20 && count % 2 == 0)
        var versionCount = 24
        if let index = CommandLine.arguments.firstIndex(of: "--versions") {
            guard CommandLine.arguments.indices.contains(index + 1),
                  let value = Int(CommandLine.arguments[index + 1]), value > 0 else {
                FileHandle.standardError.write(Data("--versions requires a positive integer\n".utf8))
                exit(64)
            }
            versionCount = value
        }
        let interactive = CommandLine.arguments.contains("--interactive")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMH-UI-Performance-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "NMH.UI.Performance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: root) }
        let settingsStore = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        if interactive {
            try settingsStore.updateSettings {
                $0.outputFolder = StoredFolderLocation(url: root.appendingPathComponent("Output"))
            }
        }
        let context = ToolContext(registeredToolCount: 1,
            settingsStore: settingsStore,
            outputInboxStore: JSONOutputInboxStore(storageURL: root.appendingPathComponent("inbox.json")),
            jobRunner: JobRunner(), fileActions: NoFileActions(), diagnostics: SilentDiagnostics())
        let runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.fixtureRootKey: root.path,
            MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1"])
        let metadataStore = stageOnly
            ? try SQLiteSongUserMetadataStore(databaseURL: root.appendingPathComponent("stage-fixture.sqlite"))
            : nil
        let model = ArchiveBrowserViewModel(context: context, songMetadataStore: metadataStore, runtime: runtime)
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let songs = try (0..<count).map { i -> Song in
            let title = "\(i % 2 == 0 ? "Neon Hook" : "Ocean Drive") \(i)"
            let folder = root.appendingPathComponent("song-\(i)")
            let versions = (0..<versionCount).map { v in
                ProjectVersion(filePath: folder.appendingPathComponent("\(title) v\(v).cpr"),
                    fileName: "\(title) v\(v).cpr", modifiedAt: date.addingTimeInterval(Double(i * 30 + v)),
                    detectedVersionNumber: v)
            }
            if detailOnly || interactive {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                for version in versions { try Data("UI fixture".utf8).write(to: version.filePath) }
            }
            var previews = [PreviewCandidate]()
            if interactive {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("\(title) mix.wav")
                let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050 * 4)!
                buffer.frameLength = buffer.frameCapacity
                for frame in 0..<Int(buffer.frameLength) {
                    buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 220 / 22050) * 0.015)
                }
                let audio = try AVAudioFile(forWriting: url, settings: format.settings)
                try audio.write(from: buffer)
                previews = [PreviewCandidate(filePath: url, fileName: url.lastPathComponent,
                    folderRole: .mixdown, modifiedAt: date, detectedRole: .mainMix, durationSeconds: 4)]
            }
            return Song(folderPath: folder, originalFolderName: title, displayTitle: title,
                projectVersions: versions, previewCandidates: previews,
                mainPreviewCandidateID: previews.first?.id, aliases: ["Demo \(i)"], collaboratorNames: ["Maria"],
                workflowStatus: ProjectWorkflowStatus.allCases[i % ProjectWorkflowStatus.allCases.count])
        }
        model.scannedSongs = songs
        model.songs = songs
        model.filteredSongs = ArchiveBrowseSortMode.sort(songs, mode: .recentCPR)
        model.needsFirstRunOnboarding = false
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1440, height: 900),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let windowDelegate = BenchmarkWindowDelegate()
        window.delegate = windowDelegate
        window.title = "Niko Music Hub — Disposable UI Performance Fixture"
        window.isReleasedWhenClosed = false
        let controller = ScrollController()
        let host = NSHostingView(rootView: BenchmarkRoot(context: context, model: model, controller: controller))
        // The harness owns its fixed window size; avoid measuring standalone host
        // ideal/min/max sizing probes on every update.
        host.sizingOptions = []
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.10)) }
        func render() {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
        }
        var rows = [[String: Any]]()
        func measure(_ name: String, prepare: (Int) -> Void = { _ in }, operation: (Int) -> Void) {
            var samples = [Double]()
            var cpuSamples = [Double]()
            var first = 0.0
            for i in 0..<18 {
                prepare(i)
                settle()
                autoreleasepool {
                    let start = CACurrentMediaTime()
                    let cpuStart = threadCPUTime()
                    operation(i)
                    let cpuElapsed = (threadCPUTime() - cpuStart) * 1000
                    let elapsed = (CACurrentMediaTime() - start) * 1000
                    if i == 0 { first = elapsed }
                    if i >= 3 { samples.append(elapsed); cpuSamples.append(cpuElapsed) }
                }
            }
            let sorted = samples.sorted()
            rows.append(["workflow": name, "first_ms": first, "samples_ms": samples,
                         "median_ms": sorted[sorted.count / 2], "min_ms": sorted.first!, "max_ms": sorted.last!,
                         "main_thread_cpu_samples_ms": cpuSamples, "main_thread_cpu_median_ms": cpuSamples.sorted()[cpuSamples.count / 2]])
            FileHandle.standardError.write(Data("Measured \(name): \(sorted[sorted.count / 2]) ms\n".utf8))
        }
        settle(); render(); settle()
        if interactive {
            withExtendedLifetime(windowDelegate) { NSApplication.shared.run() }
            return
        }
        if stageOnly {
            model.viewMode = .board
            let songID = model.filteredSongs[0].id
            render(); settle()
            measure("board_stage_change_SQLite_and_layout") { i in
                let song = model.songs.first(where: { $0.id == songID })!
                model.updateWorkflowStatus(for: song, status: i % 2 == 0 ? .songstarterBeat : .song)
                render()
            }
            let persisted = try metadataStore!.loadAll()
            precondition(persisted[songID]?.workflowStatus == .song)
            precondition(model.filteredSongs.first(where: { $0.id == songID })?.workflowStatus == .song)
        } else if detailOnly {
            model.viewMode = .boardDetail
            model.selectSong(model.filteredSongs[0])
            render(); settle()
            measure("detail_expand_\(versionCount)_CPR_rows", prepare: { _ in
                model.songDetailsExpanded = false; render()
            }) { _ in
                model.songDetailsExpanded = true; render()
            }
        } else {
            if !CommandLine.arguments.contains("--search-only") {
                for mode in [ArchiveBrowserViewModel.ArchiveViewMode.board, .list] {
                    let name = mode == .board ? "board" : "list"
                    model.viewMode = mode; model.selectedSong = nil; model.searchQuery = ""
                    model.filteredSongs = ArchiveBrowseSortMode.sort(songs, mode: .recentCPR)
                    render(); settle()
                    measure("\(name)_selection_layout") { i in
                        if mode == .board { model.selectSongOnBoard(model.filteredSongs[i % 10]) }
                        else { model.selectSong(model.filteredSongs[i % 10]) }
                        render()
                    }
                    measure("\(name)_typing_layout") { i in
                        model.setSearchQuery(i % 2 == 0 ? "neon" : "neon h")
                        // This metric isolates typing before the 200ms debounce expires.
                        model.browseRefreshDriver.cancelPendingDebounce()
                        render()
                    }
                    let expectedSearch = ["neon hook", "ocean drive"].map { query in
                        var state = model.browseState(); state.searchQuery = query
                        return ArchiveBrowseProjection.project(state)
                    }
                    measure("\(name)_search_results_layout") { i in
                        model.setSearchQuery(i % 2 == 0 ? "neon hook" : "ocean drive", immediate: true)
                        render()
                        precondition(model.filteredSongs == expectedSearch[i % 2].filteredSongs)
                    }
                    model.setSearchQuery("", immediate: true); render(); settle()
                    measure("\(name)_status_update_layout") { i in
                        model.statusMessage = "Fixture scan progress \(i)"
                        render()
                    }
                    model.statusMessage = nil
                    model.selectedSong = nil; render(); settle()
                    if mode == .list {
                        measure("list_scroll_layout") { i in
                            controller.scrollTarget = songs[min(count - 1, (i % 6) * 10)].id
                            render()
                        }
                    }
                    measure("\(name)_resize_layout") { i in
                        window.setContentSize(NSSize(width: i % 2 == 0 ? 1280 : 1440, height: 900))
                        render()
                    }
                }
                measure("metadata_chips_\(count)") { _ in
                    var labels = 0
                    for song in songs { labels += SongCardMetadataChipBuilder.chips(for: song, matchSummary: nil).count }
                    precondition(labels == count * 4)
                }
            }
            for mode in [ArchiveBrowserViewModel.ArchiveViewMode.board, .list] {
                model.viewMode = mode; model.selectedSong = nil
                model.setSearchQuery("", immediate: true); render(); settle()
                let name = mode == .board ? "board" : "list"
                var gaps = [Double](), latencies = [Double](), cpuGaps = [Double]()
                for i in 0..<10 {
                    let query = i % 2 == 0 ? "neon hook" : "ocean drive"
                    var state = model.browseState(); state.searchQuery = query
                    let expected = ArchiveBrowseProjection.project(state)
                    var received = false
                    let subscription = model.$filteredSongs.dropFirst().sink { value in
                        if value == expected.filteredSongs { received = true }
                    }
                    let probe = HeartbeatProbe()
                    let timer = Timer(timeInterval: 0.002, target: probe, selector: #selector(HeartbeatProbe.tick), userInfo: nil, repeats: true)
                    RunLoop.main.add(timer, forMode: .default)
                    let start = CACurrentMediaTime()
                    model.setSearchQuery(query)
                    while !received && CACurrentMediaTime() - start < 10 {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                    }
                    precondition(received, "Search did not complete")
                    render()
                    let latency = (CACurrentMediaTime() - start) * 1000
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    timer.invalidate(); subscription.cancel()
                    precondition(model.searchMatchSummaries == expected.searchMatchSummaries)
                    if i >= 3 { gaps.append(probe.gaps.max() ?? 0); cpuGaps.append(probe.cpuGaps.max() ?? 0); latencies.append(latency) }
                    settle()
                }
                for (metric, samples) in [("maximum_main_runloop_gap", gaps), ("maximum_main_runloop_cpu_work", cpuGaps), ("debounced_search_latency", latencies)] {
                    let sorted = samples.sorted()
                    rows.append(["workflow": "\(name)_\(metric)", "samples_ms": samples,
                                 "median_ms": sorted[sorted.count / 2], "min_ms": sorted.first!, "max_ms": sorted.last!])
                    FileHandle.standardError.write(Data("Measured \(name)_\(metric): \(sorted[sorted.count / 2]) ms\n".utf8))
                }
            }
        }
        let result: [String: Any] = ["song_count": count, "versions_per_song": versionCount,
            "window_points": [1440, 900], "hosting_sizing_options": "none; fixture window owns its size",
            "heartbeat_interval_ms": 2, "search_warmups": 3, "search_measured_iterations": 7, "warmup_iterations": 3, "measured_iterations": 15,
            "scope": "Synchronous main-thread mutation + NSHostingView layout + display + CATransaction flush. Not GPU presentation or input-to-photon latency. No audio playback.",
            "metrics": rows]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
