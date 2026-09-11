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
let report: [String: Any] = ["songs": count, "warmup_rounds": 2, "measured_rounds": 7,
                             "index_rebuild_ms": buildMS, "peak_rss_bytes": usage.ru_maxrss,
                             "queries": rows]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
