import AppCore
import Darwin
import Foundation
import NikoMusicCore
@testable import FeatureArchiveBrowser

// Headless startup-path benchmark for a large archive (the bake-off 10k archive).
//
//   script/benchmark_archive_startup.sh --archive <CubaseArchive> --database <archive-index.sqlite> \
//       [--runs N] [--warmups N] [phase ...]
//
// Phases (default: all): snapshot-load, metadata-load, cache-load, scan, cache-save,
// status-history, analytics-history, inbox-load.
//
// The database is COPIED to a temporary folder first; the original and the archive are only read.
// Output is one JSON object on stdout (medians, spread, run count) and a human table on stderr.

private struct Sample {
    let name: String
    let samples: [Double]
    /// Process CPU time (all threads) for each run: far less sensitive to other load on the Mac than wall time.
    let cpuSamples: [Double]
    let detail: [String: String]
    var cpuMedian: Double { cpuSamples.sorted()[cpuSamples.count / 2] }
    var sorted: [Double] { samples.sorted() }
    var median: Double { sorted[sorted.count / 2] }
    var minimum: Double { sorted.first ?? 0 }
    var maximum: Double { sorted.last ?? 0 }
    var p90: Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))] }
}

private func processCPUMilliseconds() -> Double {
    var value = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value)
    return Double(value.tv_sec) * 1000 + Double(value.tv_nsec) / 1e6
}

private typealias Timing = (wall: Double, cpu: Double)

private func timed(_ body: () throws -> Void) rethrows -> Timing {
    let clock = ContinuousClock()
    let cpuStart = processCPUMilliseconds()
    let start = clock.now
    try body()
    let elapsed = clock.now - start
    return (Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15,
            processCPUMilliseconds() - cpuStart)
}

private func timedAsync(_ body: () async throws -> Void) async rethrows -> Timing {
    let clock = ContinuousClock()
    let cpuStart = processCPUMilliseconds()
    let start = clock.now
    try await body()
    let elapsed = clock.now - start
    return (Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15,
            processCPUMilliseconds() - cpuStart)
}

private func peakRSSMiB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}

private func currentFootprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// FNV-1a over the sorted-key JSON of a value: a regression signature for "same output as before".
private func digest<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else { return "encode-failed" }
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return String(hash, radix: 16)
}

private struct SilentDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

@main
struct ArchiveStartupBenchmark {
    /// The app runs its cache load and scan as user-initiated tasks; a shell-launched process starts at
    /// utility QoS, which the scheduler may place on efficiency cores. Match the app.
    static func main() async throws {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0)
        var archivePath: String?
        var databasePath: String?
        var runs = 7
        var warmups = 1
        var phases: [String] = []
        var inboxCount = 2_000
        var arguments = Array(CommandLine.arguments.dropFirst())[...]
        while let argument = arguments.popFirst() {
            switch argument {
            case "--archive": archivePath = arguments.popFirst()
            case "--database": databasePath = arguments.popFirst()
            case "--runs": runs = Int(arguments.popFirst() ?? "") ?? runs
            case "--warmups": warmups = Int(arguments.popFirst() ?? "") ?? warmups
            case "--inbox-count": inboxCount = Int(arguments.popFirst() ?? "") ?? inboxCount
            default: phases.append(argument)
            }
        }
        guard let archivePath, let databasePath else {
            FileHandle.standardError.write(Data("usage: archive-startup --archive <dir> --database <sqlite> [--runs N] [--warmups N] [phase ...]\n".utf8))
            exit(64)
        }
        let allPhases = ["snapshot-load", "metadata-load", "cache-load", "scan", "cache-save",
                         "status-history", "analytics-history", "inbox-load"]
        if phases.isEmpty { phases = allPhases }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("NMH-Startup-Bench-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let databaseURL = work.appendingPathComponent("archive-index.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databasePath + suffix)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: URL(fileURLWithPath: databaseURL.path + suffix))
            }
        }
        let archive = URL(fileURLWithPath: archivePath, isDirectory: true)
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        let collaboratorStore = try SQLiteCollaboratorStore(database: database)
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: indexStore,
            songMetadataStore: metadataStore,
            collaboratorStore: collaboratorStore,
            diagnostics: SilentDiagnostics()
        )
        let collaborators = (try? collaboratorStore.loadAll()) ?? []

        var results: [Sample] = []
        func record(_ name: String, _ timings: [Timing], detail: [String: String] = [:]) {
            let sample = Sample(name: name, samples: timings.map(\.wall), cpuSamples: timings.map(\.cpu), detail: detail)
            results.append(sample)
            let line = String(format: "%-28@ wall median %9.2f ms (min %9.2f max %9.2f)  cpu median %9.2f ms  runs %d\n",
                              name as NSString, sample.median, sample.minimum, sample.maximum, sample.cpuMedian, timings.count)
            FileHandle.standardError.write(Data(line.utf8))
        }
        func repeatSync(_ body: () throws -> Void) rethrows -> [Timing] {
            for _ in 0..<warmups { try body() }
            return try (0..<runs).map { _ in try autoreleasepool { try timed(body) } }
        }

        var snapshotSongs: [Song] = []
        for phase in phases {
            switch phase {
            case "snapshot-load":
                var loaded: [Song] = []
                let samples = try repeatSync {
                    loaded = try indexStore.loadLatest()?.songs ?? []
                }
                record("snapshot-load", samples, detail: ["songs": "\(loaded.count)", "digest": digest(loaded)])
            case "metadata-load":
                var count = 0
                let samples = try repeatSync {
                    count = try metadataStore.loadAllWithReport().metadata.count
                }
                record("metadata-load", samples, detail: ["rows": "\(count)"])
            case "cache-load":
                var loaded: [Song] = []
                for _ in 0..<warmups { _ = await coordinator.loadCachedSongsReportDetached(roots: [archive], collaborators: collaborators) }
                var samples: [Timing] = []
                for _ in 0..<runs {
                    samples.append(await timedAsync {
                        let report = await coordinator.loadCachedSongsReportDetached(roots: [archive], collaborators: collaborators)
                        if case .loaded(let songs, _) = report.result { loaded = songs }
                    })
                }
                record("cache-load", samples, detail: ["songs": "\(loaded.count)", "digest": digest(loaded)])
            case "scan":
                var count = 0
                var skipped = 0
                var scanDigest = ""
                let footprintBefore = currentFootprintMiB()
                let samples = try repeatSync {
                    let result = try MusicArchiveScanner().scan(roots: [archive])
                    count = result.songs.count
                    skipped = result.skippedEntries.count
                    snapshotSongs = result.songs
                }
                scanDigest = digest(snapshotSongs)
                record("scan", samples, detail: [
                    "songs": "\(count)", "skipped": "\(skipped)", "digest": scanDigest,
                    "peak_rss_mib": String(format: "%.0f", peakRSSMiB()),
                    "footprint_before_mib": String(format: "%.0f", footprintBefore)
                ])
            case "cache-save":
                if snapshotSongs.isEmpty {
                    snapshotSongs = try indexStore.loadLatest()?.songs ?? []
                }
                // Steady state: every row unchanged (the common relaunch rescan) ...
                let snapshot = ArchiveIndexSnapshot(roots: [archive.path], songs: snapshotSongs, scannedAt: Date())
                let unchanged = try repeatSync { try indexStore.save(snapshot) }
                record("cache-save-unchanged", unchanged, detail: ["songs": "\(snapshotSongs.count)"])
                // ... and a detached save as the app does it.
                var detachedSamples: [Timing] = []
                for _ in 0..<runs {
                    detachedSamples.append(await timedAsync {
                        _ = await coordinator.persistCachedIndexDetached(roots: [archive], songs: snapshotSongs, scannedAt: Date())
                    })
                }
                record("cache-save-detached", detachedSamples, detail: ["songs": "\(snapshotSongs.count)"])
            case "status-history":
                let ids = try indexStore.loadLatest()?.songs.map(\.id) ?? []
                guard !ids.isEmpty else { break }
                // Oldest songs first in the archive (index 0 = 2010), newest last.
                let sampled: [(String, String)] = [
                    ("old", ids[min(10, ids.count - 1)]),
                    ("middle", ids[ids.count / 2]),
                    ("new", ids[max(0, ids.count - 10)])
                ]
                for (label, id) in sampled {
                    var rows: [WorkflowStatusChange] = []
                    let samples = try repeatSync {
                        for _ in 0..<50 { rows = try metadataStore.statusHistory(forSongID: id) }
                    }
                    record("status-history-x50-\(label)", samples, detail: ["rows": "\(rows.count)", "digest": digest(rows)])
                }
            case "analytics-history":
                var history: [WorkflowStatusChange] = []
                let samples = try repeatSync { history = try metadataStore.loadAllStatusHistory() }
                record("status-history-all", samples, detail: ["rows": "\(history.count)", "digest": digest(history)])
            case "inbox-load":
                // Output Inbox history: `--inbox-count` (default 2,000) real small files, steady state (all available).
                let files = work.appendingPathComponent("inbox-files")
                try fm.createDirectory(at: files, withIntermediateDirectories: true)
                var items: [OutputInboxItem] = []
                for index in 0..<inboxCount {
                    let url = files.appendingPathComponent(String(format: "take-%05d.wav", index))
                    try Data(repeating: UInt8(index & 0xFF), count: 64).write(to: url)
                    items.append(OutputInboxItem(
                        fileURL: url, sourceToolID: "benchmark",
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                        status: .available))
                }
                let inboxURL = work.appendingPathComponent("output-inbox.json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(items).write(to: inboxURL, options: .atomic)
                let store = JSONOutputInboxStore(storageURL: inboxURL)
                var count = 0
                record("inbox-list-items", try repeatSync { count = try store.listItems().count }, detail: ["entries": "\(count)"])
                record("inbox-refreshed-items", try repeatSync { count = try store.loadRefreshedItems().count }, detail: ["entries": "\(count)"])
            default:
                FileHandle.standardError.write(Data("unknown phase \(phase)\n".utf8))
                exit(64)
            }
        }

        var payload: [[String: Any]] = []
        for sample in results {
            payload.append([
                "name": sample.name, "median_ms": sample.median, "min_ms": sample.minimum,
                "max_ms": sample.maximum, "p90_ms": sample.p90, "runs": sample.samples.count,
                "samples_ms": sample.samples, "cpu_samples_ms": sample.cpuSamples,
                "cpu_median_ms": sample.cpuMedian, "detail": sample.detail
            ])
        }
        let document: [String: Any] = ["runs": runs, "warmups": warmups, "results": payload]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
