import AppCore
import AppKit
import FeatureAudioConverter
import FeatureAudioRecorder
import FeatureBPMTapper
import FeatureDownloader
import FeatureStemSeparation
import NikoMusicCore
import QuartzCore
import SwiftUI
@testable import FeatureArchiveBrowser

// First-open cost of each tool screen, the way the shell opens one: the pane is built the first time it is
// selected (`ToolPaneCache.ensureMounted`), so "opening a screen" is `makeView` plus the first layout.
//
//   script/benchmark_archive_startup.sh tools [--runs N]
//
// Each run builds the view in a fresh NSHostingView inside an isolated settings suite and output folder.
// Times are main-thread wall ms: construct = `feature.makeView(context:)`, first = first layout + display +
// CATransaction flush, second = the same again once the pane has settled (a revisit through the cache
// shows the already-built pane, so this is the cost of a plain re-layout). One JSON object on stdout.

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

@main
@MainActor
struct ToolScreensBenchmark {
    static func main() throws {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        var runs = 5
        var arguments = Array(CommandLine.arguments.dropFirst())[...]
        if arguments.first == "tools" { arguments.removeFirst() }
        while let argument = arguments.popFirst() {
            if argument == "--runs" { runs = Int(arguments.popFirst() ?? "") ?? runs }
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("NMH-Tools-Bench-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let suite = "NMH.Tools.Performance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let suitePlist = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: suitePlist)
            try? fm.removeItem(at: work)
        }
        let settingsStore = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        try settingsStore.updateSettings { $0.outputFolder = StoredFolderLocation(url: work.appendingPathComponent("Output")) }
        let router = QuickAccessRouter()
        let context = ToolContext(
            settingsStore: settingsStore,
            preferences: UserDefaultsPreferenceStore(userDefaults: defaults),
            outputInboxStore: JSONOutputInboxStore(storageURL: work.appendingPathComponent("inbox.json")),
            jobRunner: JobRunner(),
            fileActions: NoFileActions(),
            diagnostics: SilentDiagnostics(),
            router: router
        )

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 820),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        let features: [(String, any ToolFeature)] = [
            ("BPM Tapper", BPMTapperFeature()),
            ("Audio Converter", AudioConverterFeature(router: router)),
            ("Audio Recorder", AudioRecorderFeature()),
            ("Downloader", DownloaderFeature()),
            ("Stem Separation", StemSeparationFeature()),
        ]
        func milliseconds(_ body: () -> Void) -> Double {
            let start = CACurrentMediaTime()
            body()
            return (CACurrentMediaTime() - start) * 1000
        }
        func settle(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        var rows: [[String: Any]] = []
        for (name, feature) in features {
            var construct: [Double] = [], first: [Double] = [], second: [Double] = []
            for _ in 0..<(runs + 1) {
                autoreleasepool {
                    let host = NSHostingView(rootView: AnyView(EmptyView()))
                    host.sizingOptions = []
                    window.contentView = host
                    settle(0.1)
                    var view = AnyView(EmptyView())
                    let built = milliseconds { view = feature.makeView(context: context) }
                    let displayed = milliseconds {
                        host.rootView = view
                        host.needsLayout = true
                        host.layoutSubtreeIfNeeded()
                        window.displayIfNeeded()
                        CATransaction.flush()
                    }
                    settle(0.5)
                    let again = milliseconds {
                        host.needsLayout = true
                        host.layoutSubtreeIfNeeded()
                        window.displayIfNeeded()
                        CATransaction.flush()
                    }
                    construct.append(built); first.append(displayed); second.append(again)
                    window.contentView = NSView()
                }
                settle(0.2)
            }
            // The first run of a process pays one-time costs (framework loads); keep it visible, not in the median.
            func summary(_ values: [Double]) -> [String: Any] {
                let rest = Array(values.dropFirst()).sorted()
                return ["first_run_ms": values.first ?? 0, "median_ms": rest[rest.count / 2], "min_ms": rest.first ?? 0, "max_ms": rest.last ?? 0]
            }
            rows.append(["tool": name, "construct": summary(construct), "first_layout": summary(first), "second_layout": summary(second)])
            FileHandle.standardError.write(Data(String(format: "%-18@ construct %7.2f ms  first layout %7.2f ms  relayout %7.2f ms (first run: %.1f / %.1f)\n",
                name as NSString, summary(construct)["median_ms"] as! Double, summary(first)["median_ms"] as! Double,
                summary(second)["median_ms"] as! Double, construct.first ?? 0, first.first ?? 0).utf8))
        }
        let data = try JSONSerialization.data(withJSONObject: ["runs": runs, "tools": rows], options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
}
