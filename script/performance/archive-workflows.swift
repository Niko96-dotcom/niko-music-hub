import Foundation
import NikoMusicCore
import Darwin

@main
struct ArchiveWorkflowBenchmark {
    static func main() throws {
        let clock = ContinuousClock()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMHPerformance-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let labels = ["Neon Hook", "Gravity", "Glühwurm", "Silver Lining", "Ocean Drive"]
        let stages = ["demo", "mix", "master", "session bounce", "sketch", "prod"]
        let songs = (0..<1000).map { i -> Song in
            let title = "\(labels[i % labels.count]) \(i)"
            let folder = URL(fileURLWithPath: "/benchmark-only/\(title)")
            let versions = (1...24).map { v in
                ProjectVersion(filePath: folder.appendingPathComponent("\(title) v\(v).cpr"),
                    fileName: "\(title) v\(v).cpr", modifiedAt: now.addingTimeInterval(-Double((i * 47 + v * 13) % 365) * 86400),
                    detectedVersionNumber: v)
            }
            let previews = (1...36).map { v in
                PreviewCandidate(filePath: folder.appendingPathComponent("\(title) \(stages[v % stages.count]) v\(v).wav"),
                    fileName: "\(title) \(stages[v % stages.count]) v\(v).wav", folderRole: .mixdown,
                    modifiedAt: now.addingTimeInterval(-Double((i * 31 + v * 11) % 300) * 86400),
                    detectedRole: .mainMix, detectedVersionNumber: v, durationSeconds: 180)
            }
            return Song(folderPath: folder, originalFolderName: title, displayTitle: title,
                projectVersions: versions, previewCandidates: previews,
                aliases: ["Demo \(i)"], collaboratorNames: ["Maria", "Jun"],
                workflowStatus: ProjectWorkflowStatus.allCases[i % ProjectWorkflowStatus.allCases.count],
                ignoredCPRVersionIDs: i % 5 == 0 ? [versions[0].id, versions[2].id] : [])
        }
        let heavyPreviews = (0..<1200).map { i in
            PreviewCandidate(filePath: URL(fileURLWithPath: "/benchmark-only/Neon Hook \(stages[i % stages.count]) v\(i % 24 + 1) \(i).wav"),
                fileName: "Neon Hook \(stages[i % stages.count]) v\(i % 24 + 1) \(i).wav",
                folderRole: .mixdown, modifiedAt: now.addingTimeInterval(Double(i)),
                detectedRole: .mainMix, detectedVersionNumber: i % 24 + 1, durationSeconds: 180)
        }
        let context = PreviewRankingProjectContext(anchorCPRVersion: 24, titleTokens: ["neon", "hook"])
        var metrics = [[String: Any]]()
        func ms(_ duration: Duration) -> Double {
            let p = duration.components
            return Double(p.seconds) * 1000 + Double(p.attoseconds) / 1e15
        }
        func digest(_ text: String) -> String {
            var value: UInt64 = 14695981039346656037
            for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
            return String(value, radix: 16)
        }
        func measure<T>(_ name: String, _ operation: () throws -> T, output: (T) throws -> String) throws {
            var samples = [Double]()
            var expected: String?
            var first = 0.0
            for iteration in 0..<10 {
                try autoreleasepool {
                    let start = clock.now
                    let value = try operation()
                    let elapsed = ms(start.duration(to: clock.now))
                    let signature = digest(try output(value))
                    if let expected { precondition(signature == expected, "Output changed: \(name)") }
                    else { expected = signature; first = elapsed }
                    if iteration >= 3 { samples.append(elapsed) }
                }
            }
            FileHandle.standardError.write(Data("Measured \(name)\n".utf8))
            let sorted = samples.sorted()
            metrics.append(["workflow": name, "first_ms": first, "median_ms": sorted[3],
                            "min_ms": sorted.first!, "max_ms": sorted.last!, "samples_ms": samples,
                            "digest": expected!])
        }
        func songIDs(_ songs: [Song]) -> String { songs.map(\.id).joined(separator: "\n") }
        func rankedOutput(_ previews: [PreviewCandidate]) -> String {
            previews.map { "\($0.id)|\($0.confidenceScore)|\($0.confidenceReasons.joined(separator: ","))" }.joined(separator: "\n")
        }
        try measure("rank_36_previews", { PreviewConfidenceRanker().rank(songs[0].previewCandidates, projectContext: context) }, output: rankedOutput)
        try measure("rank_1200_previews", { PreviewConfidenceRanker().rank(heavyPreviews, projectContext: context) }, output: rankedOutput)
        for mode in ArchiveBrowseSortMode.allCases {
            try measure("sort_1000_\(mode.rawValue)", { ArchiveBrowseSortMode.sort(songs, mode: mode) }, output: songIDs)
        }
        try measure("board_1000", { ArchiveBoardProjection.columns(from: songs) }, output: {
            $0.map { "\($0.id):\(songIDs($0.songs))" }.joined(separator: "\n")
        })
        let calendar = Calendar(identifier: .gregorian)
        try measure("analytics_1000", { ArchiveAnalyticsProjection.snapshot(songs: songs, history: [], now: now, calendar: calendar) }, output: {
            "\($0.overview)|\($0.monthlyActivity)|\($0.stageDistribution)"
        })
        let store = try SQLiteArchiveIndexStore(databaseURL: root.appendingPathComponent("archive.sqlite"))
        let snapshot = ArchiveIndexSnapshot(roots: ["/benchmark-only"], songs: songs, scannedAt: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Setup excluded: load and unchanged save represent repeated app use.
        try autoreleasepool { try store.save(snapshot) }
        try measure("sqlite_load_1000", { try store.loadLatest() }, output: {
            String(decoding: try encoder.encode($0), as: UTF8.self)
        })
        try measure("sqlite_save_unchanged_1000", { try store.save(snapshot) }, output: { _ in
            String(decoding: try encoder.encode(store.loadLatest()), as: UTF8.self)
        })
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        try autoreleasepool {
            try metadataStore.upsertAll(songs.map { SongUserMetadata.from(song: $0, updatedAt: now) })
        }
        try measure("metadata_load_1000", { try metadataStore.loadAll() }, output: {
            String(decoding: try encoder.encode($0), as: UTF8.self)
        })
        let scanRoot = root.appendingPathComponent("Archive")
        // Valid mono PCM WAV, 50 ms. Fixture creation is outside scan timing.
        var wav = Data()
        func bytes(_ s: String) { wav.append(contentsOf: s.utf8) }
        func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        bytes("RIFF"); u32(36 + 4410); bytes("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(44100); u32(88200); u16(2); u16(16); bytes("data"); u32(4410)
        wav.append(Data(repeating: 0, count: 4410))
        for i in 0..<50 {
            let folder = scanRoot.appendingPathComponent("\(labels[i % labels.count]) \(i)")
            let mixes = folder.appendingPathComponent("Mixdown")
            try fm.createDirectory(at: mixes, withIntermediateDirectories: true)
            for v in 1...4 { try Data("fixture".utf8).write(to: folder.appendingPathComponent("Song \(i) v\(v).cpr")) }
            for v in 1...12 { try wav.write(to: mixes.appendingPathComponent("Song \(i) \(stages[v % stages.count]) v\(v).wav")) }
        }
        if let entries = fm.enumerator(at: scanRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in entries {
                try fm.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            }
        }
        try measure("scan_50_songs_600_previews", { try CubaseArchiveScanner().scan(roots: [scanRoot]) }, output: {
            // Scanner time changes per call; compare complete songs only, in a stable order.
            String(decoding: try encoder.encode($0.songs.sorted { $0.id < $1.id }), as: UTF8.self)
                .replacingOccurrences(of: scanRoot.path, with: "/fixture/Archive")
        })
        if CommandLine.arguments.contains("--extended") {
            let builder = VaultManifestBuilder()
            let manifestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            try measure("vault_manifest_800_files", {
                try builder.build(at: scanRoot, id: manifestID, createdAt: now)
            }, output: { manifest in
                manifest.entries.map { "\($0.relativePath)|\($0.byteCount)|\($0.sha256 ?? "")" }.joined(separator: "\n")
            })
            let manifest = try builder.build(at: scanRoot, id: manifestID, createdAt: now)
            try measure("vault_verify_800_files", { try builder.verify(manifest, at: scanRoot) },
                        output: { _ in "verified" })
            let frames = 44100 * 12
            wav = Data()
            bytes("RIFF"); u32(UInt32(36 + frames * 4)); bytes("WAVEfmt "); u32(16); u16(3); u16(1)
            u32(44100); u32(176400); u16(4); u16(32); bytes("data"); u32(UInt32(frames * 4))
            for i in 0..<frames {
                let time = Double(i) / 44100
                let amplitude = time < 4 ? 0.1 : 0.25
                var sample = Float(amplitude * (sin(time * 2 * .pi * 261.6256)
                    + sin(time * 2 * .pi * 329.6276) + sin(time * 2 * .pi * 391.9954)))
                withUnsafeBytes(of: &sample) { wav.append(contentsOf: $0) }
            }
            let audioURL = root.appendingPathComponent("analysis.wav")
            try wav.write(to: audioURL)
            try measure("bpm_estimate_12s", { MixdownBPMEstimator.estimate(url: audioURL) },
                        output: { String(describing: $0) })
            try measure("key_estimate_12s", { MixdownKeyEstimator.estimate(url: audioURL) },
                        output: { String(describing: $0) })
            try measure("hook_locate_12s", { PreviewHookLocator.hookStartSecondsSync(for: audioURL) },
                        output: { String(describing: $0) })
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
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
        let report: [String: Any] = ["warmup_rounds": 2, "measured_rounds": 7, "songs": 1000,
                                   "peak_rss_bytes": usage.ru_maxrss, "metrics": metrics,
                                   "host": hostInfo, "build_config": buildConfig,
                                   "scope": "Catalog/sort/board/analytics/SQLite plus 50-song scan and optional 800-small-file manifest/verify. Heavy Vault manifests (100/1000/10000 records) and catalog/transfer reconciliation live in script/performance/vault-recovery.swift; this file does not duplicate them. No caps/discard; digests guard output parity.",
                                   "budgets": "Host-specific guidance only, not a universal SLA. Sort/board/analytics feed background refresh and cached panes; keeping 1000-song medians within a frame budget on the reporting host leaves scrolling and typing responsive. Coordinator validates on the exact host/config in this report."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
