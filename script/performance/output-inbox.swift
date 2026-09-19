import AppCore
import Darwin
import Foundation

// Output Inbox refresh benchmark (reproducible, fixture-only).
//
// Measures the production refresh path on N DISTINCT 64-byte files with a
// steady-state inbox (all records `available` after warmup):
//   baseline:  refreshAvailability() + listItems()  (two JSON loads + two sorts)
//   optimized: loadRefreshedItems()                 (one JSON load + one sort)
//
// Both paths do the same per-file availability stat work; the optimized path
// only removes the redundant second JSON load/sort. Moving that work off the
// main actor (OutputInboxRefreshModel) is covered by
// Tests/AppCoreTests/OutputInboxRefreshTests.swift, not by this script: total
// work here must NOT be claimed faster solely because it moved threads.
let sizes: [Int] = {
    guard let raw = CommandLine.arguments.dropFirst().first else { return [100, 1000, 10000] }
    let parsed = raw.split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
    return parsed.isEmpty ? [100, 1000, 10000] : parsed
}()
let measuredRounds = 5
let fileBytes = 64

let clock = ContinuousClock()
func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
}

func digest(_ items: [OutputInboxItem]) -> String {
    var value: UInt64 = 14695981039346656037
    for item in items {
        let text = "\(item.id)|\(item.status.rawValue)|\(item.fileURL.lastPathComponent)\n"
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
    }
    return String(value, radix: 16)
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

/// Builds a fixture inbox: N distinct 64-byte files + one inbox.json written
/// directly (one encode, so setup stays O(N)). Deterministic content/dates.
func makeFixture(count: Int) throws -> (directory: URL, store: JSONOutputInboxStore) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("nmh-inbox-benchmark")
        .appendingPathComponent(UUID().uuidString)
    let files = directory.appendingPathComponent("files")
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    var items: [OutputInboxItem] = []
    items.reserveCapacity(count)
    for index in 0..<count {
        let url = files.appendingPathComponent(String(format: "take-%05d.wav", index))
        try Data(repeating: UInt8(index & 0xFF), count: fileBytes).write(to: url)
        items.append(OutputInboxItem(
            fileURL: url,
            sourceToolID: "benchmark",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            status: .pending
        ))
    }
    let storage = directory.appendingPathComponent("output-inbox.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(items).write(to: storage, options: .atomic)
    return (directory, JSONOutputInboxStore(storageURL: storage))
}

func measureBaseline(_ store: JSONOutputInboxStore) throws -> [OutputInboxItem] {
    try store.refreshAvailability()
    return try store.listItems()
}

var sizeRows: [[String: Any]] = []
for count in sizes {
    let baselineFixture = try makeFixture(count: count)
    let optimizedStorage = baselineFixture.directory.appendingPathComponent("optimized-inbox.json")
    try FileManager.default.copyItem(
        at: baselineFixture.directory.appendingPathComponent("output-inbox.json"),
        to: optimizedStorage
    )
    let optimizedFixture = (store: JSONOutputInboxStore(storageURL: optimizedStorage), directory: baselineFixture.directory)
    defer {
        try? FileManager.default.removeItem(at: baselineFixture.directory)
    }

    // Warmup: settle both fixtures to steady state (pending -> available).
    let warmBaseline = try measureBaseline(baselineFixture.store)
    let warmOptimized = try optimizedFixture.store.loadRefreshedItems()
    precondition(warmBaseline.count == count && warmOptimized.count == count, "fixture setup lost records")
    precondition(digest(warmBaseline) == digest(warmOptimized), "paths disagree on fixture snapshot")

    var baselineSamples: [Double] = []
    var optimizedSamples: [Double] = []
    var expected = ""
    for round in 0..<(measuredRounds + 1) {
        let startBaseline = clock.now
        let baselineItems = try measureBaseline(baselineFixture.store)
        let baselineMS = milliseconds(startBaseline.duration(to: clock.now))

        let startOptimized = clock.now
        let optimizedItems = try optimizedFixture.store.loadRefreshedItems()
        let optimizedMS = milliseconds(startOptimized.duration(to: clock.now))

        precondition(baselineItems.count == count, "baseline dropped records")
        precondition(optimizedItems.count == count, "optimized dropped records")
        let snapshotDigest = digest(baselineItems)
        precondition(digest(optimizedItems) == snapshotDigest, "paths disagree in round \(round)")
        if round == 0 {
            expected = snapshotDigest
        } else {
            precondition(snapshotDigest == expected, "non-repeatable refresh output")
            baselineSamples.append(baselineMS)
            optimizedSamples.append(optimizedMS)
        }
    }

    sizeRows.append([
        "items": count,
        "file_bytes": fileBytes,
        "baseline_ms": [
            "median": median(baselineSamples),
            "min": baselineSamples.min()!,
            "max": baselineSamples.max()!,
            "samples": baselineSamples,
        ] as [String: Any],
        "optimized_ms": [
            "median": median(optimizedSamples),
            "min": optimizedSamples.min()!,
            "max": optimizedSamples.max()!,
            "samples": optimizedSamples,
        ] as [String: Any],
        "digest": expected,
    ])
}

var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let report: [String: Any] = [
    "tool": "output-inbox-refresh",
    "measured_rounds": measuredRounds,
    "steady_state": "pending warmed to available; rounds measure load + stat + sort with save skipped (unchanged)",
    "scope": "refreshAvailability+listItems total work only; main-thread responsiveness is covered by OutputInboxRefreshTests, not claimed here",
    "peak_rss_bytes": usage.ru_maxrss,
    "sizes": sizeRows,
]
print(String(data: try JSONSerialization.data(
    withJSONObject: report,
    options: [.prettyPrinted, .sortedKeys]
), encoding: .utf8)!)
