import AppCore
import AppKit
import Combine
import Darwin
import Foundation
import NikoMusicCore
import QuartzCore
import SwiftUI
@testable import FeatureArchiveBrowser

// What a playing archive preview costs the main thread.
//
//   script/benchmark_archive_startup.sh playback --archive <CubaseArchive> [--song "Amber Moth"]
//       [--seconds 5] [--sizing default|none]
//
// It builds the archive view model the way AppComposition does, mounts the real ArchiveBrowserView
// with the ArchivePersistentPlayerView below it (the shell's layout), waits for the scan, then measures
// two windows of the same length: the song's preview loaded but paused, and the same preview playing
// (volume 0). Per window: main-thread CPU share, process CPU share, and main run-loop stalls (2 ms
// heartbeat; a gap over 8.3 ms misses a 120 Hz frame, over 16.7 ms a 60 Hz frame). `--sizing default`
// keeps NSHostingView's own sizing options, as the app's window does; `none` turns them off like
// archive-launch.swift. One JSON object goes to stdout.

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

@MainActor
private final class Heartbeat: NSObject {
    private var last = CACurrentMediaTime()
    private(set) var gaps: [Double] = []

    @objc func tick() {
        let now = CACurrentMediaTime()
        gaps.append((now - last) * 1000)
        last = now
    }

    func reset() {
        gaps.removeAll(keepingCapacity: true)
        last = CACurrentMediaTime()
    }
}

private struct ShellLikeRoot: View {
    let context: ToolContext
    let model: ArchiveBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            ArchiveBrowserView(context: context, viewModel: model)
            ArchivePersistentPlayerView(viewModel: model) {}
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

@main
struct ArchivePlaybackBenchmark {
    @MainActor
    static func main() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var archivePath: String?
        var songTitle = "Amber Moth"
        var seconds = 5.0
        var sizing = "default"
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            func value() -> String { arguments.isEmpty ? "" : arguments.removeFirst() }
            switch argument {
            case "--archive": archivePath = value()
            case "--song": songTitle = value()
            case "--seconds": seconds = Double(value()) ?? seconds
            case "--sizing": sizing = value()
            default:
                FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
                exit(64)
            }
        }
        guard let archivePath else {
            FileHandle.standardError.write(Data("usage: archive-playback --archive <dir> [--song title] [--seconds s] [--sizing default|none]\n".utf8))
            exit(64)
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("NMH-Playback-Bench-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let suite = "NMH.Playback.Performance.\(UUID())"
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
            $0.musicRoots = [StoredMusicRoot(role: .scanOnly, displayName: "Playback Archive", pathFallback: archive.path)]
            $0.archiveOnboardingCompleted = true
            $0.outputFolder = StoredFolderLocation(url: work.appendingPathComponent("Output"))
        }
        let context = ToolContext(
            settingsStore: settingsStore,
            preferences: UserDefaultsPreferenceStore(userDefaults: defaults),
            outputInboxStore: JSONOutputInboxStore(storageURL: work.appendingPathComponent("inbox.json")),
            jobRunner: JobRunner(),
            fileActions: NoFileActions(),
            diagnostics: SilentDiagnostics(),
            processRunner: FoundationExternalProcessRunner(processGroups: LiveProcessGroupRegistry())
        )
        let runtime = MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.dryRunOpenKey: "1"])

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()

        let database = try SQLiteArchiveDatabase(databaseURL: work.appendingPathComponent("archive-index.sqlite"))
        let model = ArchiveBrowserViewModel(
            context: context,
            archiveIndexStore: try SQLiteArchiveIndexStore(database: database),
            songMetadataStore: try SQLiteSongUserMetadataStore(database: database),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            collaboratorStore: try SQLiteCollaboratorStore(database: database),
            runtime: runtime
        )
        var cancellables = Set<AnyCancellable>()
        var scanStarted = false
        var scanFinished = false
        model.library.$isScanning.sink { scanning in
            if scanning { scanStarted = true }
            if !scanning, scanStarted { scanFinished = true }
        }.store(in: &cancellables)

        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Niko Music Hub — Playback Benchmark"
        let host = NSHostingView(rootView: ShellLikeRoot(context: context, model: model))
        if sizing == "none" { host.sizingOptions = [] }
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()

        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let scanDeadline = CACurrentMediaTime() + 300
        while !scanFinished && CACurrentMediaTime() < scanDeadline { run(0.005) }
        guard scanFinished else {
            FileHandle.standardError.write(Data("scan did not finish\n".utf8))
            exit(1)
        }
        run(1.0)
        guard let song = model.songs.first(where: { $0.effectiveDisplayTitle == songTitle }) else {
            FileHandle.standardError.write(Data("no song titled \(songTitle) among \(model.songs.count) songs\n".utf8))
            exit(1)
        }

        let heartbeat = Heartbeat()
        let timer = Timer(timeInterval: 0.002, target: heartbeat, selector: #selector(Heartbeat.tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)

        let player = model.previewSession.player
        func measure(_ name: String) -> [String: Any] {
            heartbeat.reset()
            let wallStart = CACurrentMediaTime(), mainStart = threadCPUTime(), processStart = processCPUTime()
            let positionStart = player.currentTime
            run(seconds)
            let wall = CACurrentMediaTime() - wallStart
            let gaps = heartbeat.gaps
            return [
                "window": name,
                "seconds": wall,
                "main_thread_cpu_pct": (threadCPUTime() - mainStart) / wall * 100,
                "process_cpu_pct": (processCPUTime() - processStart) / wall * 100,
                "stalls_over_8ms": gaps.filter { $0 > 8.3 }.count,
                "stalls_over_17ms": gaps.filter { $0 > 16.7 }.count,
                "max_stall_ms": gaps.max() ?? 0,
                "playback_advanced_s": player.currentTime - positionStart,
                "is_playing": model.previewSession.isPlaying,
            ]
        }

        model.previewSession.volume = 0
        model.audition(song)
        let loadDeadline = CACurrentMediaTime() + 10
        while (player.duration <= 0 || player.currentTime <= 0) && CACurrentMediaTime() < loadDeadline { run(0.01) }
        model.previewSession.toggle()
        run(1.0)
        let paused = measure("paused")
        model.previewSession.toggle()
        run(1.0)
        let playing = measure("playing")
        model.previewSession.toggle()

        let result: [String: Any] = [
            "songs": model.songs.count,
            "sizing": sizing,
            "duration_s": player.duration,
            "windows": [paused, playing],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        window.close()
    }
}
