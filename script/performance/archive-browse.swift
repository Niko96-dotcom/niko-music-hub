import Foundation
import NikoMusicCore
import Darwin

// Reproducible large-library browse benchmark (release, in-memory only).
// Fixture paths are identifiers under /fixture-only; no real files are read.
// Compiles against both baseline and candidate: uses only
// ArchiveBrowseProjection.project(_:searchIndex:), .shelfSongs(from:),
// MusicSearchIndex(songs:) and .sync(from:).
// Timed region per round is exactly: shelf derivation + warm index.sync +
// project(state, searchIndex:) for nonempty queries (empty control is just
// project(state)). Digests (JSON, sorted keys, FNV-1a) are computed OUTSIDE
// the timed region and asserted stable per round.

@main
struct ArchiveBrowseBenchmark {
    static func main() throws {
        let clock = ContinuousClock()
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count <= 1 else {
            FileHandle.standardError.write(Data("Usage: archive-browse [count>0]\n".utf8))
            exit(1)
        }
        let rawCount = args.first ?? "1000"
        guard let count = Int(rawCount), count > 0 else {
            FileHandle.standardError.write(Data("Usage: archive-browse [count>0]\n".utf8))
            exit(1)
        }
        // Deterministic anchors (no wall-clock): all fixed in the past so the
        // quiet shelf (unfinished CPRs older than 30 days) is stably the
        // unfinished subset for current and future runs — both far from threshold.
        let recentAnchor = Date(timeIntervalSince1970: 1_200_000_000)
        let oldAnchor = Date(timeIntervalSince1970: 1_000_000_000)
        let previewAnchor = Date(timeIntervalSince1970: 1_750_000_000)
        let labels = ["Neon Hook", "Ocean Drive", "Silver Lining", "Gravity", "Gluhwurm"]
        let query = "neon"

        func makeCatalog(_ n: Int) -> [Song] {
            (0..<n).map { i -> Song in
                let base = labels[i % labels.count]
                let title = "\(base) \(i)"
                let folder = URL(fileURLWithPath: "/fixture-only/\(title)")
                let recentDays = 5.0 + Double((i * 13) % 10)
                let oldDays = Double((i * 17) % 100)
                let useRecent = i % 2 == 0
                let versions: [ProjectVersion] = (0..<4).map { v in
                    let date: Date
                    if useRecent {
                        date = recentAnchor.addingTimeInterval(-(recentDays + Double(v * 2)) * 86_400)
                    } else {
                        date = oldAnchor.addingTimeInterval((oldDays + Double(v * 3)) * 86_400)
                    }
                    let name = "\(title) v\(v + 1).cpr"
                    return ProjectVersion(
                        filePath: folder.appendingPathComponent(name),
                        fileName: name,
                        modifiedAt: date
                    )
                }
                let previews: [PreviewCandidate] = (0..<6).map { v in
                    let role: PreviewFolderRole
                    let detected: PreviewDetectedRole
                    if v == 0 {
                        role = .mixdown
                        detected = .mainMix
                    } else if v == 1, i % 3 == 0 {
                        role = .stems
                        detected = .stems
                    } else {
                        role = v % 2 == 0 ? .mixdown : .samples
                        detected = v % 2 == 0 ? .mainMix : .preview
                    }
                    let days = 3.0 + Double((i * 29 + v * 13) % 180)
                    let name = "\(title) preview v\(v + 1).wav"
                    return PreviewCandidate(
                        filePath: folder.appendingPathComponent(name),
                        fileName: name,
                        folderRole: role,
                        modifiedAt: previewAnchor.addingTimeInterval(-days * 86_400),
                        detectedRole: detected
                    )
                }
                let collaboratorID = "collab-\(i % 3)"
                let collaboratorNames: [String]
                switch i % 3 {
                case 0: collaboratorNames = ["Maria Klein"]
                case 1: collaboratorNames = ["Jun Park"]
                default: collaboratorNames = ["Maria Klein", "Jun Park"]
                }
                return Song(
                    folderPath: folder,
                    originalFolderName: title,
                    displayTitle: title,
                    projectVersions: versions,
                    previewCandidates: previews,
                    scanWarnings: i % 4 == 0 ? ["missing preview"] : [],
                    sidecarNotes: i % 5 == 0 ? "Sidecar note \(i)" : nil,
                    aliases: ["Demo \(i)", "Alias \(i % 20)"],
                    appNote: i % 3 == 0 ? "Studio note \(i)" : nil,
                    collaboratorIDs: [collaboratorID],
                    collaboratorNames: collaboratorNames,
                    workflowStatus: ProjectWorkflowStatus.allCases[i % ProjectWorkflowStatus.allCases.count],
                    isIgnored: i % 10 == 0
                )
            }
        }

        let songs = makeCatalog(count)

        func ms(_ duration: Duration) -> Double {
            let p = duration.components
            return Double(p.seconds) * 1000 + Double(p.attoseconds) / 1e15
        }
        func fnv(_ text: String) -> String {
            var value: UInt64 = 14695981039346656037
            for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
            return String(value, radix: 16)
        }
        struct SkippedDigest: Codable {
            var label: String
            var reason: String
            var kind: String
            var score: Int
            var details: [String]
        }
        struct ResultDigest: Codable {
            var ids: [String]
            var songs: [Song]
            var summaries: [String: String]
            var skipped: [SkippedDigest]
            var isSearching: Bool
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func encodeResult(_ result: ArchiveBrowseResult) throws -> String {
            let payload = ResultDigest(
                ids: result.filteredSongs.map(\.id),
                songs: result.filteredSongs,
                summaries: result.searchMatchSummaries,
                skipped: result.skippedSearchMatches.map {
                    SkippedDigest(
                        label: $0.entry.label,
                        reason: $0.entry.reason,
                        kind: $0.entry.kind.rawValue,
                        score: $0.score,
                        details: $0.details.map { "\($0.queryToken):\($0.kind.rawValue):\($0.score)" }
                    )
                },
                isSearching: result.isSearching
            )
            return String(decoding: try encoder.encode(payload), as: UTF8.self)
        }

        var metrics = [[String: Any]]()

        func measure(
            _ name: String,
            shelf: ArchiveSmartShelf,
            searchQuery: String,
            shelfCount: Int,
            warmInitMs: Double?,
            operation: () -> ArchiveBrowseResult
        ) throws {
            var samples = [Double]()
            var expected: String?
            var first = 0.0
            var filteredCount = 0
            for iteration in 0..<10 {
                try autoreleasepool {
                    let start = clock.now
                    let value = operation()
                    let elapsed = ms(start.duration(to: clock.now))
                    // Digest OUTSIDE the timed region; no validation inside timing.
                    let signature = fnv(try encodeResult(value))
                    filteredCount = value.filteredSongs.count
                    if let expected {
                        precondition(signature == expected, "Output changed: \(name)")
                    } else {
                        expected = signature
                        first = elapsed
                    }
                    if iteration >= 3 { samples.append(elapsed) }
                }
            }
            FileHandle.standardError.write(Data("Measured \(name)\n".utf8))
            let sorted = samples.sorted()
            var row: [String: Any] = [
                "workflow": name,
                "shelf": shelf.rawValue,
                "query": searchQuery,
                "first_ms": first,
                "median_ms": sorted[3],
                "min_ms": sorted.first!,
                "max_ms": sorted.last!,
                "samples_ms": samples,
                "digest": expected!,
                "shelf_count": shelfCount,
                "filtered_count": filteredCount,
            ]
            if let warmInitMs { row["warm_index_init_ms"] = warmInitMs }
            metrics.append(row)
        }

        func searchState(shelf: ArchiveSmartShelf, query: String) -> ArchiveBrowseState {
            ArchiveBrowseState(
                songs: songs,
                showHiddenSongs: false,
                selectedShelf: shelf,
                selectedCollaboratorID: shelf == .byCollaborator ? "collab-1" : nil,
                searchQuery: query,
                browseFilter: [],
                sortMode: .recentCPR,
                skippedScanEntries: []
            )
        }

        // Empty-query control: pure shelf derive/filter/sort, no index.
        do {
            let state = searchState(shelf: .allSongs, query: "")
            let shelfCount = ArchiveBrowseProjection.shelfSongs(from: state).count
            try measure(
                "empty_control_allSongs",
                shelf: .allSongs,
                searchQuery: "",
                shelfCount: shelfCount,
                warmInitMs: nil
            ) {
                ArchiveBrowseProjection.project(state)
            }
        }

        // Nonempty queries: full shelf derivation + warm sync + scoped project.
        let searchShelves: [ArchiveSmartShelf] = [
            .allSongs, .byCollaborator, .recentCPRActivity, .recentlyBounced, .quietSongs,
        ]
        for shelf in searchShelves {
            let state = searchState(shelf: shelf, query: query)
            let warmShelf = ArchiveBrowseProjection.shelfSongs(from: state)
            let initStart = clock.now
            var index = MusicSearchIndex(songs: warmShelf)
            let initMs = ms(initStart.duration(to: clock.now))
            let shelfCount = warmShelf.count
            try measure(
                "search_\(shelf.rawValue)_neon",
                shelf: shelf,
                searchQuery: query,
                shelfCount: shelfCount,
                warmInitMs: initMs
            ) {
                let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
                index.sync(from: onShelf)
                return ArchiveBrowseProjection.project(state, searchIndex: index)
            }
        }

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let process = ProcessInfo.processInfo
        let hostInfo: [String: Any] = [
            "os": process.operatingSystemVersionString,
            "cpu_count": process.processorCount,
            "physical_memory_bytes": Int64(process.physicalMemory),
        ]
#if DEBUG
        let buildConfig = "debug"
#else
        let buildConfig = "release"
#endif
        let fixture: [String: Any] = [
            "songs": count,
            "versions_per_song": 4,
            "previews_per_song": 6,
            "method": "synthetic deterministic in-memory catalog; fixture-only paths, no real files; fixed epoch anchors (no wall-clock) so digests are stable across A/B runs",
            "recent_cpr_anchor": 1_200_000_000,
            "recent_cpr_days": "5-21 before anchor (2008, always quiet when unfinished; safely far from 30-day threshold)",
            "old_cpr_anchor": 1_000_000_000,
            "old_cpr_days": "0-108 after anchor (2001, always quiet when unfinished; safely far from threshold)",
            "collaborator_ids": "collab-0/1/2 (byCollaborator uses collab-1)",
            "ignored_fraction": "1/10 (showHiddenSongs=false)",
            "status": "cycled ProjectWorkflowStatus.allCases",
            "warnings_aliases_notes": "warnings every 4th, aliases all, appNote every 3rd, sidecar every 5th",
            "query": query,
            "query_coverage": "matches Neon Hook subset; every 10th song hidden removes half the Neon group, so roughly 1/9 of visible songs match",
        ]
        let report: [String: Any] = [
            "songs": count,
            "warmup_rounds": 2,
            "measured_rounds": 7,
            "peak_rss_bytes": usage.ru_maxrss,
            "metrics": metrics,
            "fixture": fixture,
            "host": hostInfo,
            "build_config": buildConfig,
            "scope": "Full production shelf derivation + warm MusicSearchIndex.sync(from:) + ArchiveBrowseProjection.project(state, searchIndex:) for nonempty queries across allSongs/byCollaborator/recentCPRActivity/recentlyBounced/quietSongs plus empty-query control. Digests cover full ordered Song values, summaries, skipped matches and isSearching via sorted-keys JSON outside timing. Same driver runs for baseline and candidate; coordinator compares digests A/B/B/A at small/large scales.",
            "budgets": "Host-specific guidance only, not a universal SLA. Coordinator validates medians on the exact host/config in this report.",
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
