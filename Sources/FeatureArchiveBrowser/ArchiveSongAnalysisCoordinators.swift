import AppCore
import Foundation
import NikoMusicCore

/// BPM/key analysis for the active preview file. Owned by ``ArchiveBrowserViewModel``.
@MainActor
final class ArchiveMixdownAnalysisCoordinator {
    private var analysisTask: Task<Void, Never>?

    /// BPM/key must key off the active preview file, not just song folder id.
    static func cacheKey(for song: Song) -> String? {
        guard let previewID = song.mainPreviewCandidateID else { return nil }
        return "\(song.id)|\(previewID)"
    }

    func bpmEstimate(for song: Song, in cache: [String: MixdownBPMEstimate]) -> MixdownBPMEstimate? {
        guard let key = Self.cacheKey(for: song) else { return nil }
        return cache[key]
    }

    func keyEstimate(for song: Song, in cache: [String: MixdownKeyEstimate]) -> MixdownKeyEstimate? {
        guard let key = Self.cacheKey(for: song) else { return nil }
        return cache[key]
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    static func invalidate(
        for songID: String,
        bpmCache: inout [String: MixdownBPMEstimate],
        keyCache: inout [String: MixdownKeyEstimate]
    ) {
        bpmCache = bpmCache.filter { !$0.key.hasPrefix("\(songID)|") }
        keyCache = keyCache.filter { !$0.key.hasPrefix("\(songID)|") }
    }

    static func prune(
        remainingSongIDs: Set<String>,
        bpmCache: inout [String: MixdownBPMEstimate],
        keyCache: inout [String: MixdownKeyEstimate]
    ) {
        bpmCache = bpmCache.filter { entry in
            remainingSongIDs.contains(where: { entry.key.hasPrefix("\($0)|") })
        }
        keyCache = keyCache.filter { entry in
            remainingSongIDs.contains(where: { entry.key.hasPrefix("\($0)|") })
        }
    }

    func refresh(
        for song: Song,
        bpmCache: [String: MixdownBPMEstimate],
        keyCache: [String: MixdownKeyEstimate],
        isStillSelected: @escaping @MainActor (String, String) -> Bool,
        apply: @escaping @MainActor (String, MixdownBPMEstimate?, MixdownKeyEstimate?) -> Void
    ) {
        cancel()
        guard let cacheKey = Self.cacheKey(for: song) else { return }
        let needsBPM = bpmCache[cacheKey] == nil
        let needsKey = keyCache[cacheKey] == nil
        guard needsBPM || needsKey else { return }
        let songID = song.id
        let url = song.previewCandidates.first(where: { $0.id == song.mainPreviewCandidateID })?.filePath
        guard let url else { return }
        analysisTask = Task {
            let bpmEstimate: MixdownBPMEstimate?
            let keyEstimate: MixdownKeyEstimate?
            if needsBPM, needsKey {
                async let bpm = Task.detached(priority: .utility) {
                    MixdownBPMEstimator.estimate(url: url)
                }.value
                async let key = Task.detached(priority: .utility) {
                    MixdownKeyEstimator.estimate(url: url)
                }.value
                bpmEstimate = await bpm
                keyEstimate = await key
            } else if needsBPM {
                bpmEstimate = await Task.detached(priority: .utility) {
                    MixdownBPMEstimator.estimate(url: url)
                }.value
                keyEstimate = nil
            } else {
                bpmEstimate = nil
                keyEstimate = await Task.detached(priority: .utility) {
                    MixdownKeyEstimator.estimate(url: url)
                }.value
            }
            guard !Task.isCancelled, isStillSelected(songID, cacheKey) else { return }
            apply(cacheKey, needsBPM ? bpmEstimate : nil, needsKey ? keyEstimate : nil)
        }
    }
}

/// CPR plugin summary loading for the selected song. Owned by ``ArchiveBrowserViewModel``.
@MainActor
final class ArchiveCPRPluginCoordinator {
    private var loadTask: Task<Void, Never>?
    private let processRunner: any ExternalProcessRunning

    init(processRunner: any ExternalProcessRunning = FoundationExternalProcessRunner()) {
        self.processRunner = processRunner
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    static func invalidate(path: String, cache: inout [String: CPRPluginSummary]) {
        cache.removeValue(forKey: path)
    }

    func summary(for song: Song, in cache: [String: CPRPluginSummary]) -> CPRPluginSummary? {
        guard let cpr = song.effectiveLatestCPR else { return nil }
        return cache[cpr.filePath.standardizedFileURL.path]
    }

    func refresh(
        for song: Song,
        cache: [String: CPRPluginSummary],
        isStillSelected: @escaping @MainActor (String) -> Bool,
        apply: @escaping @MainActor (String, CPRPluginSummary) -> Void
    ) {
        cancel()
        guard let cpr = song.effectiveLatestCPR else { return }
        let path = cpr.filePath.standardizedFileURL.path
        guard cache[path] == nil else { return }
        let songID = song.id
        let processRunner = processRunner
        loadTask = Task {
            let summary = await CPRPluginSummaryService.loadPlugins(
                cprURL: cpr.filePath,
                subprocessRunner: { cprURL in
                    do {
                        let result = try await processRunner.run(
                            ExternalProcessRequest(
                                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                                arguments: ["cubase-project-plugins", cprURL.path],
                                timeoutSeconds: 5
                            )
                        )
                        guard result.exitCode == 0 else { return nil }
                        return CPRPluginSummaryService.parsePluginListOutput(result.standardOutput)
                    } catch {
                        return nil
                    }
                }
            )
            guard !Task.isCancelled, isStillSelected(songID) else { return }
            apply(path, summary)
        }
    }
}
