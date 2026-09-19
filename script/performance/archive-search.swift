import Foundation
import NikoMusicCore
import Darwin

// In-memory catalog only: these paths are identifiers; no music files are read or written.
let count = Int(CommandLine.arguments.dropFirst().first ?? "1000") ?? 1000
precondition(count > 0)
let titles = ["Neon Hook", "Velvet Morning", "Glühwurm", "Gravity", "Ocean Drive",
              "Silver Lining", "Summer Rain", "Midnight Call", "Paper Planes", "Golden Hour"]
let collaborators = ["Maria Klein", "Jun Park", "Sofia Müller", "Alex Kim"]
let songs = (0..<count).map { i -> Song in
    let title = titles[i % titles.count] + " \(i)"
    let folder = URL(fileURLWithPath: "/benchmark-only/Session \(i)/\(title)")
    let versions = (1...4).map { version in
        ProjectVersion(filePath: folder.appendingPathComponent("\(title) v\(version).cpr"),
                       fileName: "\(title) v\(version).cpr", modifiedAt: .distantPast)
    }
    let previews = (1...6).map { version in
        PreviewCandidate(filePath: folder.appendingPathComponent("Mixdown/\(title) v\(version) mix.wav"),
                         fileName: "\(title) v\(version) mix.wav", folderRole: .mixdown,
                         modifiedAt: .distantPast, detectedRole: .mainMix)
    }
    return Song(folderPath: folder, originalFolderName: "2026 Session \(i) \(title)",
                displayTitle: title, projectVersions: versions, previewCandidates: previews,
                scanWarnings: i % 7 == 0 ? ["Missing reference preview"] : [],
                sidecarNotes: "Writing session with \(collaborators[i % 4]). Try the alternate chorus.",
                aliases: ["Working title \(i)", "Demo \(i)"],
                appNote: i % 3 == 0 ? "Final vocal awaiting approval" : "Revise second verse",
                collaboratorNames: [collaborators[i % 4]])
}
let clock = ContinuousClock()
func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
}
var index = MusicSearchIndex()
let buildStart = clock.now
index.rebuild(from: songs)
let buildMS = milliseconds(buildStart.duration(to: clock.now))
let queries = ["neon", "neon hook", "maria final", "gravity v3 mix", "noen hook", "gluhwurm", "zzzz absent", "hook neon", "gluhwurm maria", "silver lining", "summer rain"]
// Stable FNV-1a digest of ordered IDs, scores and explanations guards benchmark parity.
func digest(_ results: [MusicSearchResult]) -> String {
    var value: UInt64 = 14695981039346656037
    for result in results {
        let text = "\(result.song.id)|\(result.score)|\(result.matchSummary)\n"
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
    }
    return String(value, radix: 16)
}
var samples = Array(repeating: [Double](), count: queries.count)
var first = [Double]()
var signatures = [String]()
var resultCounts = [Int]()
for query in queries {
    let start = clock.now
    let result = index.searchResults(query)
    first.append(milliseconds(start.duration(to: clock.now)))
    signatures.append(digest(result))
    resultCounts.append(result.count)
}
// Two complete warmups, then seven rounds with rotated query order to reduce ordering bias.
for round in 0..<9 {
    for offset in queries.indices {
        let position = (offset + round) % queries.count
        let start = clock.now
        let result = index.searchResults(queries[position])
        let elapsed = milliseconds(start.duration(to: clock.now))
        precondition(digest(result) == signatures[position], "Non-repeatable search output")
        if round >= 2 { samples[position].append(elapsed) }
    }
}
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let rows: [[String: Any]] = queries.indices.map { i in
    let sorted = samples[i].sorted()
    return ["query": queries[i], "first_ms": first[i], "median_ms": sorted[sorted.count / 2],
            "min_ms": sorted.first!, "max_ms": sorted.last!, "samples_ms": samples[i],
            "result_count": resultCounts[i], "digest": signatures[i]]
}
// Invalidation probe: rebuild cost is measured, not hidden. Mutating song
// metadata without a sync/rebuild must not change results; a rebuild must
// reflect the change. Uses public virtualTitle so the script sees the same
// invalidation contract as production (sync(from:)/rebuild(from:) refresh
// searchable rows; production syncs incrementally and skips empty queries).
var mutatedSongs = songs
mutatedSongs[0].virtualTitle = "Invalidation Probe ZZ Top Unique Title"
var mutatedIndex = MusicSearchIndex()
let rebuildProbeStart = clock.now
mutatedIndex.rebuild(from: mutatedSongs)
let rebuildProbeMS = milliseconds(rebuildProbeStart.duration(to: clock.now))
let unrebuiltDigest = digest(index.searchResults(queries[0]))
precondition(unrebuiltDigest == signatures[0], "Index changed without rebuild")
let mutatedDigest = digest(mutatedIndex.searchResults(queries[0]))
precondition(mutatedDigest != signatures[0], "Rebuild did not reflect metadata change")
let invalidation: [String: Any] = ["rebuild_ms": rebuildProbeMS, "query": queries[0],
    "before_digest": signatures[0], "after_digest": mutatedDigest, "unrebuilt_stable": true]
// Optional baseline parity: coordinator passes --baseline <path> to compare the
// deterministic digest (ordered IDs, scores, explanations) against an unchanged
// baseline. Guards ranking/order/fuzzy/diacritics/conjunction/explanation.
var baselineCheck: [String: Any] = ["checked": false]
if let flag = CommandLine.arguments.firstIndex(of: "--baseline"),
   CommandLine.arguments.indices.contains(flag + 1) {
    let baselineURL = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    let baselineData = try Data(contentsOf: baselineURL)
    let baseline = try JSONSerialization.jsonObject(with: baselineData) as! [String: Any]
    let baselineQueries = baseline["queries"] as! [[String: Any]]
    precondition(baselineQueries.count == queries.count, "Baseline query count mismatch")
    precondition((baseline["songs"] as? Int) == count, "Baseline song count mismatch")
    for (i, row) in baselineQueries.enumerated() {
        precondition((row["query"] as! String) == queries[i], "Baseline query order mismatch")
        precondition((row["digest"] as! String) == signatures[i],
            "Digest mismatch for query \(queries[i]): ranking/order/fuzzy semantics changed")
        precondition((row["result_count"] as! Int) == resultCounts[i],
            "Result count mismatch for query \(queries[i])")
    }
    baselineCheck = ["checked": true, "path": CommandLine.arguments[flag + 1],
                     "matched_queries": queries.count]
}
let process = ProcessInfo.processInfo
let hostInfo: [String: Any] = ["hostname": process.hostName,
    "os": process.operatingSystemVersionString,
    "cpu_count": process.processorCount,
    "physical_memory_bytes": Int64(process.physicalMemory)]
#if DEBUG
let buildConfig = "debug"
#else
let buildConfig = "release"
#endif
let report: [String: Any] = ["songs": count, "warmup_rounds": 2, "measured_rounds": 7,
                             "index_rebuild_ms": buildMS, "peak_rss_bytes": usage.ru_maxrss,
                             "queries": rows, "invalidation": invalidation,
                             "baseline": baselineCheck, "host": hostInfo,
                             "build_config": buildConfig,
                             "scope": "In-memory MusicSearchIndex.searchResults only; no music files read. Rebuild precomputes normalized fields/tokens once per song and is timed separately (index_rebuild_ms plus invalidation rebuild_ms) with peak RSS via getrusage. No caps/discard: every song is scored per query.",
                             "budgets": "Host-specific guidance only, not a universal SLA. Typing search drives a debounced background query; keeping the 1000-song median near the checked-in baseline (~60ms max on the evidence host) leaves main-thread frames and concurrent scan/analysis responsive. 10000-song medians (319-631ms on the evidence host) belong off the typing fast path; coordinator validates on the exact host/config in this report."]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
