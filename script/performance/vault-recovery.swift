import Foundation
import NikoMusicCore
import Darwin

// Vault recovery reconciliation benchmark (deterministic, fixture-only).
//
// Measures production-code, safe read-only/reconciliation paths on realistic
// Vault manifests with DISTINCT files and representative manifest records at
// 100/1000/10000 records with explicit payload sizes:
//
//   - VaultManifestBuilder.build / verify / validatePersistedContentEnvelope /
//     hasSameImmutableContent on a fixture tree beneath a UUID temp root.
//   - SQLiteVaultTransferStore save / load-all / recoverable / verified-generation
//     plus VaultTransferRecoveryPolicy.candidates (pure in-memory).
//   - ProjectCatalogReconciler.reconcile (pure in-memory) and
//     SQLiteProjectCatalogStore apply / loadEntries.
//   - SQLiteVaultTransferStore.reconcileRestoreRecordsForRecovery (fixture DB only).
//
// What this script NEVER does (no shell worker, no real data):
//   - Never calls recoverAtLaunch copy faults or any LocalVaultTransferEngine /
//     restore copy/promote path. Only safe read-only and reconciliation helpers.
//   - Fixture paths live beneath one UUID temp directory; cleanup removes only that.
//   - No huge accidental auto-retry copies: payloads are explicit small sizes
//     (64-byte .cpr, 256-byte .wav) and retries are counted, never executed.
//
// Correctness checks (outside timing, reported): verified verify succeeds,
// missing file throws, corrupt byte throws, envelope validates, catalog
// ambiguity throws, SQLite recoverable filter returns the expected subset.
// Transfer save/load and reconciliation are timed SEPARATELY with digests.

@main
struct VaultRecoveryBenchmark {
    static func main() throws {
        let clock = ContinuousClock()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMHVaultRecovery-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let scales: [Int] = {
            let raw = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }
            guard let raw else { return [100, 1000, 10000] }
            let parsed = raw.split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
            return parsed.isEmpty ? [100, 1000, 10000] : parsed
        }()
        // Explicit small payloads keep 10000-record runs bounded and honest.
        // Distinct content per file (header + pad) gives distinct SHA-256 values.
        let cprBytes = 64
        let wavBytes = 256
        let filesPerProject = 4
        let baseDate = Date(timeIntervalSince1970: 1_780_000_000)
        let rootActiveID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let rootArchiveID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        func ms(_ duration: Duration) -> Double {
            let p = duration.components
            return Double(p.seconds) * 1000 + Double(p.attoseconds) / 1e15
        }
        func digest(_ text: String) -> String {
            var value: UInt64 = 14695981039346656037
            for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
            return String(value, radix: 16)
        }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        func uuidFor(_ i: Int) -> UUID {
            // Deterministic 12-hex-digit suffix; supports well beyond 10000.
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", UInt(i % 0xFFFFFFFFFFFF)))!
        }
        func fakeSHA(_ i: Int) -> String {
            String(format: "%064x", UInt(i))
        }
        func manifestDigest(_ manifest: VaultManifest) -> String {
            digest(manifest.entries.map { "\($0.relativePath)|\($0.byteCount)|\($0.sha256 ?? "")" }.joined(separator: "\n"))
        }
        func fileData(project: Int, kind: Int, size: Int) -> Data {
            let header = "vault-fixture p\(project)k\(kind)\n"
            var data = Data(header.utf8)
            let pad = UInt8((project &* 31 &+ kind &* 7) & 0xFF)
            while data.count < size { data.append(pad) }
            return data.prefix(size)
        }

        var sizeRows: [[String: Any]] = []
        for scale in scales {
            let scaleRoot = root.appendingPathComponent("scale-\(scale)")
            let archiveRoot = scaleRoot.appendingPathComponent("archive")
            try fm.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
            // Fixture creation is OUTSIDE timing. Distinct files, grouped 4 per
            // project directory for a realistic Vault tree shape.
            let projectCount = max(1, (scale + filesPerProject - 1) / filesPerProject)
            var fileCount = 0
            for p in 0..<projectCount {
                let dir = archiveRoot.appendingPathComponent(String(format: "project-%05d", p))
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                for k in 0..<filesPerProject {
                    guard fileCount < scale else { break }
                    let isCPR = (k % 2 == 0)
                    let name = isCPR
                        ? String(format: "song-%05d v%d.cpr", p, k)
                        : String(format: "song-%05d mix v%d.wav", p, k)
                    let size = isCPR ? cprBytes : wavBytes
                    try fileData(project: p, kind: k, size: size).write(to: dir.appendingPathComponent(name))
                    fileCount += 1
                }
            }
            // Deterministic mtimes so built manifests are comparable across runs.
            if let entries = fm.enumerator(at: archiveRoot, includingPropertiesForKeys: nil) {
                for case let url as URL in entries {
                    try fm.setAttributes([.modificationDate: baseDate], ofItemAtPath: url.path)
                }
            }
            let builder = VaultManifestBuilder()
            let manifestID = uuidFor(scale)
            // Warm build for correctness checks (outside timing).
            let intact = try builder.build(at: archiveRoot, id: manifestID, createdAt: baseDate)
            try intact.validatePersistedContentEnvelope()
            try builder.verify(intact, at: archiveRoot)
            let expectedManifestDigest = manifestDigest(intact)
            let manifestTotalBytes = (try? intact.validatedTotalBytes()) ?? -1
            // Correctness: missing file must fail closed.
            let missingURL = archiveRoot.appendingPathComponent("project-00000")
            let probeMissing = missingURL.appendingPathComponent("probe-missing.cpr")
            try fileData(project: 999999, kind: 0, size: cprBytes).write(to: probeMissing)
            let withExtra = try builder.build(at: archiveRoot, id: manifestID, createdAt: baseDate)
            try fm.removeItem(at: probeMissing)
            var missingThrows = false
            do { try builder.verify(withExtra, at: archiveRoot) } catch { missingThrows = true }
            precondition(missingThrows, "verify must fail when a recorded file is missing")
            // Correctness: corrupt byte must fail closed.
            let firstFile = try fm.contentsOfDirectory(at: archiveRoot.appendingPathComponent("project-00000"), includingPropertiesForKeys: nil).first!
            let original = try Data(contentsOf: firstFile)
            var corrupt = original
            corrupt[corrupt.startIndex] = corrupt[corrupt.startIndex] ^ 0xFF
            try corrupt.write(to: firstFile)
            var corruptThrows = false
            do { try builder.verify(intact, at: archiveRoot) } catch { corruptThrows = true }
            precondition(corruptThrows, "verify must fail on corrupt content")
            try original.write(to: firstFile)
            try builder.verify(intact, at: archiveRoot)

            var metrics: [[String: Any]] = []
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
                FileHandle.standardError.write(Data("Measured \(name) scale \(scale)\n".utf8))
                metrics.append(["workflow": name, "first_ms": first,
                    "median_ms": median(samples), "min_ms": samples.min()!,
                    "max_ms": samples.max()!, "samples_ms": samples, "digest": expected!])
            }

            try measure("manifest_build_\(scale)", { try builder.build(at: archiveRoot, id: manifestID, createdAt: baseDate) }, output: { manifestDigest($0) })
            try measure("manifest_verify_\(scale)", { try builder.verify(intact, at: archiveRoot); return "verified" }, output: { $0 })
            try measure("manifest_envelope_\(scale)", { try intact.validatePersistedContentEnvelope(); return "valid" }, output: { $0 })
            try measure("manifest_identity_\(scale)", { intact.hasSameImmutableContent(as: withExtra) ? "same" : "different" }, output: { $0 })

            // Representative transfer records: deterministic IDs, mixed states,
            // small synthetic manifests with valid 64-hex digests and explicit sizes.
            func makeTransfer(_ i: Int) -> VaultTransferRecord {
                let pid = ProjectID(rawValue: uuidFor(i + scale * 100_000))
                var record = VaultTransferRecord(
                    id: uuidFor(i + 1),
                    projectID: pid,
                    sourceURL: scaleRoot.appendingPathComponent("active/project-\(i)"),
                    stagingURL: scaleRoot.appendingPathComponent("staging/\(i)"),
                    destinationURL: scaleRoot.appendingPathComponent("generations/project-\(i)"),
                    state: [.copyingToArchiveStaging, .failedRecoverable, .archiveVerified, .recoveryRequired, .superseded][i % 5],
                    createdAt: baseDate.addingTimeInterval(Double(i)))
                let entries = [
                    VaultManifest.Entry(relativePath: "Song \(i).cpr", type: .regularFile, byteCount: Int64(cprBytes), modifiedAt: baseDate, sha256: fakeSHA(i)),
                    VaultManifest.Entry(relativePath: "Mixdown/Song \(i) mix.wav", type: .regularFile, byteCount: Int64(wavBytes), modifiedAt: baseDate, sha256: fakeSHA(i + 1)),
                ]
                let manifest = VaultManifest(id: uuidFor(i + 2), createdAt: baseDate, entries: entries)
                record.manifestID = manifest.id
                record.manifest = manifest
                record.totalBytes = (try? manifest.validatedTotalBytes()) ?? 0
                record.updatedAt = baseDate.addingTimeInterval(Double(i))
                if record.state == .failedRecoverable {
                    record.retryCount = 2
                    record.error = VaultTransferError(origin: .copyingToArchiveStaging, reason: .sourceMutated, message: "fixture")
                }
                return record
            }
            let transfers = (0..<scale).map(makeTransfer)
            let blobBytes = try JSONEncoder().encode(transfers[0]).count
            // Correctness: recoverable filter returns only copying + failed states.
            let recoverableExpected = Set(transfers.filter { $0.state == .copyingToArchiveStaging || $0.state == .failedRecoverable }.map(\.id))
            // Correctness: catalog ambiguity fixture throws (outside timing).
            do {
                let dupRoot = rootActiveID
                let loc = ProjectLocation(rootID: dupRoot, relativePath: "dup", kind: .active)
                let ev = { (n: String) in ProjectIdentityEvidence(folderName: n, cubaseFiles: Set([ProjectFileIdentity(name: "A.cpr", byteCount: 1, modifiedAt: baseDate)])) }
                let e1 = ProjectCatalogEntry(record: ProjectRecord(canonicalTitle: "A", locations: [loc]), evidence: ev("A"))
                let e2 = ProjectCatalogEntry(record: ProjectRecord(canonicalTitle: "B", locations: [loc]), evidence: ev("B"))
                _ = try ProjectCatalogReconciler().reconcile(existing: [e1, e2],
                    observations: [ProjectCatalogObservation(canonicalTitle: "C", location: loc, evidence: ev("C"))])
                preconditionFailure("duplicate location must throw")
            } catch let ambiguity as ProjectCatalogReconciler.Ambiguity {
                guard case .duplicateLocation = ambiguity else { preconditionFailure("wrong ambiguity error") }
            }

            let transferDB = scaleRoot.appendingPathComponent("transfers.sqlite")
            let transferStore = try SQLiteVaultTransferStore(databaseURL: transferDB)
            // Setup excluded: populate once so load/recoverable represent repeated use.
            for record in transfers { try transferStore.save(record) }
            let savedRecoverable = try transferStore.recoverableRecords()
            precondition(Set(savedRecoverable.map(\.id)) == recoverableExpected, "recoverable filter mismatch")
            try measure("transfer_save_\(scale)", {
                for record in transfers { try transferStore.save(record) }
                return "saved \(transfers.count)"
            }, output: { $0 })
            try measure("transfer_load_all_\(scale)", { try transferStore.allTransferRecords() }, output: {
                $0.sorted { $0.id.uuidString < $1.id.uuidString }
                    .map { "\($0.id)|\($0.state.rawValue)" }.joined(separator: "\n")
            })
            try measure("transfer_recoverable_\(scale)", { try transferStore.recoverableRecords() }, output: {
                $0.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id.uuidString).joined(separator: "\n")
            })
            try measure("transfer_candidates_\(scale)", {
                VaultTransferRecoveryPolicy.candidates(from: transfers)
            }, output: {
                $0.map(\.id.uuidString).joined(separator: "\n")
            })
            // Verified-generation lookup uses a verified project when the scale
            // contains one; tiny custom scales without a verified state report "none".
            let verifiedProject = transfers.first { $0.state == .archiveVerified }?.projectID
            try measure("transfer_verified_generation_\(scale)", {
                guard let verifiedProject else { return "none" }
                return try transferStore.verifiedArchiveGeneration(projectID: verifiedProject)?.id.uuidString ?? "none"
            }, output: { $0 })

            // Catalog reconciliation: half merge at same location, half new with
            // matching folder name (creates reviews). Pure in-memory, no copies.
            let existingEntries: [ProjectCatalogEntry] = (0..<scale).map { i in
                let loc = ProjectLocation(rootID: rootActiveID, relativePath: "project-\(i)", kind: .active, lastSeenAt: baseDate)
                let evidence = ProjectIdentityEvidence(folderName: "Project \(i)",
                    cubaseFiles: Set([ProjectFileIdentity(name: "Song \(i).cpr", byteCount: Int64(1000 + i), modifiedAt: baseDate)]),
                    selectedContentHashes: Set([fakeSHA(i)]))
                let stableID = ProjectID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", i + 1))!)
                return ProjectCatalogEntry(record: ProjectRecord(id: stableID, canonicalTitle: "Project \(i)", locations: [loc]), evidence: evidence)
            }
            let observations: [ProjectCatalogObservation] = (0..<scale).map { i in
                if i < scale / 2 {
                    let loc = ProjectLocation(rootID: rootActiveID, relativePath: "project-\(i)", kind: .active, lastSeenAt: baseDate)
                    let evidence = ProjectIdentityEvidence(folderName: "Project \(i)",
                        cubaseFiles: Set([ProjectFileIdentity(name: "Song \(i).cpr", byteCount: Int64(1000 + i), modifiedAt: baseDate)]),
                        selectedContentHashes: Set([fakeSHA(i)]))
                    return ProjectCatalogObservation(canonicalTitle: "Project \(i)", location: loc, evidence: evidence)
                } else {
                    let source = i - scale / 2
                    let loc = ProjectLocation(rootID: rootArchiveID, relativePath: "project-new-\(i)", kind: .archive, lastSeenAt: baseDate)
                    let evidence = ProjectIdentityEvidence(folderName: "Project \(source)",
                        cubaseFiles: Set([ProjectFileIdentity(name: "Other \(i).cpr", byteCount: Int64(2000 + i), modifiedAt: baseDate)]))
                    return ProjectCatalogObservation(canonicalTitle: "Project \(source)", location: loc, evidence: evidence)
                }
            }
            let reconciler = ProjectCatalogReconciler()
            let reconciledOnce = try reconciler.reconcile(existing: existingEntries, observations: observations, observedAt: baseDate)
            precondition(reconciledOnce.entries.count == scale + scale / 2, "catalog reconcile entry count mismatch")
            precondition(!reconciledOnce.reviews.isEmpty, "expected name-match reviews")
            precondition(reconciledOnce.reviews.count == scale / 2, "catalog review count mismatch")
            try measure("catalog_reconcile_\(scale)", {
                try reconciler.reconcile(existing: existingEntries, observations: observations, observedAt: baseDate)
            }, output: { reconciled in
                // Reconciler allocates fresh ProjectIDs (UUID()) for new candidate
                // observations on every call, so raw IDs are unstable across
                // iterations. Canonicalize newly allocated identities by stable
                // location+evidence while keeping the strict digest for persisted
                // identity/order/data: existing IDs must match exactly, counts and
                // name-match reviews are asserted, and review UUIDs/dates are
                // excluded (only count, pair keys, reason and resolution feed the digest).
                precondition(reconciled.entries.count == scale + scale / 2, "catalog reconcile entry count changed")
                precondition(reconciled.reviews.count == reconciledOnce.reviews.count, "catalog review count changed")
                precondition(!reconciled.reviews.isEmpty, "expected name-match reviews")
                let existingIDs = Set(existingEntries.map { $0.record.id })
                for existing in existingEntries {
                    let loc = existing.record.locations[0]
                    guard let match = reconciled.entries.first(where: { entry in
                        entry.record.locations.contains { $0.rootID == loc.rootID && $0.relativePath == loc.relativePath }
                    }) else {
                        preconditionFailure("existing location missing after reconcile: \(loc.relativePath)")
                    }
                    precondition(match.record.id == existing.record.id, "existing ID not retained at \(loc.relativePath)")
                }
                func stableID(for entry: ProjectCatalogEntry) -> String {
                    if existingIDs.contains(entry.record.id) {
                        return entry.record.id.description
                    }
                    let locKey = entry.record.locations
                        .map { "\($0.rootID.uuidString.lowercased())/\($0.relativePath):\($0.kind.rawValue):\($0.availability.rawValue)" }
                        .sorted().joined(separator: ",")
                    let filesKey = entry.evidence.cubaseFiles
                        .map { "\($0.normalizedName)|\($0.byteCount)" }
                        .sorted().joined(separator: ",")
                    let hashesKey = entry.evidence.selectedContentHashes.sorted().joined(separator: ",")
                    return "new:\(locKey):\(entry.evidence.normalizedFolderName):\(filesKey):\(hashesKey)"
                }
                var stableByID: [ProjectID: String] = [:]
                for entry in reconciled.entries {
                    stableByID[entry.record.id] = stableID(for: entry)
                }
                let entryRows = reconciled.entries.map { entry -> String in
                    let sid = stableByID[entry.record.id]!
                    let locs = entry.record.locations
                        .map { "\($0.rootID.uuidString.lowercased())/\($0.relativePath):\($0.kind.rawValue):\($0.availability.rawValue)" }
                        .sorted().joined(separator: ",")
                    let filesKey = entry.evidence.cubaseFiles
                        .map { "\($0.normalizedName)|\($0.byteCount)" }
                        .sorted().joined(separator: ",")
                    let hashesKey = entry.evidence.selectedContentHashes.sorted().joined(separator: ",")
                    return "\(sid)|\(entry.record.canonicalTitle)|\(locs)|\(entry.evidence.normalizedFolderName)|\(filesKey)|\(hashesKey)"
                }.sorted()
                let reviewRows = reconciled.reviews.map { review -> String in
                    let existingStable = existingIDs.contains(review.existingProjectID) ? review.existingProjectID.description : (stableByID[review.existingProjectID] ?? review.existingProjectID.description)
                    let candidateStable = stableByID[review.candidateProjectID] ?? review.candidateProjectID.description
                    precondition(existingIDs.contains(review.existingProjectID), "review existing ID unknown")
                    precondition(!existingIDs.contains(review.candidateProjectID), "review candidate should be newly allocated")
                    precondition(review.reason.contains("Names match"), "unexpected review reason")
                    return "\(existingStable)|\(candidateStable)|\(review.reason)|\(review.resolution.rawValue)"
                }.sorted()
                return entryRows.joined(separator: "\n") + "\nreviews:\(reconciled.reviews.count)\n" + reviewRows.joined(separator: "\n")
            })
            let catalogDB = scaleRoot.appendingPathComponent("catalog.sqlite")
            let catalogStore = try SQLiteProjectCatalogStore(databaseURL: catalogDB)
            try catalogStore.apply(reconciledOnce)
            try measure("catalog_save_\(scale)", { try catalogStore.apply(reconciledOnce); return "applied \(reconciledOnce.entries.count)" }, output: { $0 })
            try measure("catalog_load_\(scale)", { try catalogStore.loadEntries() }, output: {
                $0.sorted { $0.record.id.description < $1.record.id.description }
                    .map { $0.record.id.description }.joined(separator: "\n")
            })

            // Restore reconciliation on fixture DB only (no copies, no launches).
            // The restore table holds only incomplete restores (production backlog is
            // dozens, not library size), so it is measured at min(scale, 200) with an
            // explicit count in the metric name. Transfer/catalog still cover the full
            // 100/1000/10000 records; nothing is discarded from those paths.
            let restoreStore = try SQLiteVaultTransferStore(databaseURL: scaleRoot.appendingPathComponent("restores.sqlite"))
            let restoreManifest = VaultManifest(id: uuidFor(999), createdAt: baseDate, entries: [
                .init(relativePath: "Song.cpr", type: .regularFile, byteCount: Int64(cprBytes), modifiedAt: baseDate, sha256: fakeSHA(7)),
            ])
            let restoreCount = min(scale, 200)
            for i in 0..<restoreCount {
                let record = VaultRestoreRecord(
                    projectID: ProjectID(rawValue: uuidFor(500_000 + i)),
                    archiveGenerationURL: scaleRoot.appendingPathComponent("generations/project-\(i % 10)"),
                    stagingURL: scaleRoot.appendingPathComponent("restore-staging/\(i)"),
                    destinationURL: scaleRoot.appendingPathComponent("active/restored-\(i % 10)"),
                    manifest: restoreManifest,
                    createdAt: baseDate.addingTimeInterval(Double(i)))
                try restoreStore.saveRestore(record)
            }
            try measure("restore_reconcile_\(restoreCount)", {
                try restoreStore.reconcileRestoreRecordsForRecovery()
            }, output: { $0.map(\.id.uuidString).sorted().joined(separator: "\n") })

            sizeRows.append([
                "records": scale,
                "distinct_files": fileCount,
                "file_bytes_cpr": cprBytes,
                "file_bytes_wav": wavBytes,
                "manifest_entries": intact.entries.count,
                "manifest_total_bytes": manifestTotalBytes,
                "manifest_digest": expectedManifestDigest,
                "transfer_record_blob_bytes": blobBytes,
                "correctness": ["verified_ok": true, "missing_throws": missingThrows,
                    "corrupt_throws": corruptThrows, "recoverable_match": true,
                    "catalog_reviews": reconciledOnce.reviews.count] as [String: Any],
                "metrics": metrics,
            ])
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
        let report: [String: Any] = ["tool": "vault-recovery-reconciliation",
            "measured_rounds": 7, "warmup_rounds": 3,
            "scales": sizeRows,
            "peak_rss_bytes": usage.ru_maxrss,
            "host": hostInfo, "build_config": buildConfig,
            "scope": "Fixture-only under one UUID temp root (removed afterwards). Safe read-only/reconciliation only: manifest build/verify/envelope/identity, transfer SQLite save/load/recoverable/verified-generation/candidates, catalog reconcile/save/load, restore reconcile. Never runs recoverAtLaunch copy faults, LocalVaultTransferEngine/RestoreEngine copies, or auto-retry copies. Transfer save/load and reconciliation are separate metrics with digests; missing/corrupt/verified and recoverable/ambiguity correctness checks are reported, not hidden.",
            "budgets": "Host-specific guidance only, not a universal SLA. Launch recovery must not block first frame or input: manifest verify for a single 4-file project belongs in milliseconds on the reporting host; 100-record reconcile/save/load belongs in background launch work well under a second; 1000/10000-record catalog/transfer work is library-scale background maintenance and must stay off the typing/scroll path. Coordinator validates exact medians on the host/config in this report before any product budget is set."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
