#if DEBUG
import AppCore
import Foundation
import NikoMusicCore

struct AbletonFlowEvidence: SmokeValidatedEvidence, Equatable {
    let groupsCorrect: Bool
    let openedAbleton: Bool
    let openedCubase: Bool
    let manualMainPersists: Bool
    let searchFindsAbleton: Bool
    let archiveUnchanged: Bool

    func satisfiesScenario() -> Bool {
        groupsCorrect && openedAbleton && openedCubase && manualMainPersists && searchFindsAbleton && archiveUnchanged
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["ableton_mixed_song_flow"] = String(satisfiesScenario())
        log["ableton_archive_unchanged"] = String(archiveUnchanged)
    }
}

@MainActor
extension ArchiveUserFlowSmoke {
    static func runAbletonFlow(context: ToolContext) throws -> SmokeRun {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("nmh-ableton-smoke-\(UUID())")
        let root = base.appendingPathComponent("Archive")
        defer { try? FileManager.default.removeItem(at: base) }
        for (index, path) in ["Together/Song.cpr", "Together/Live/Song.als", "Separate/Other.als", "Together/Live/Backup/Old.als"].enumerated() {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic DAW project".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 100))], ofItemAtPath: url.path)
        }
        let before = try snapshotArchiveTree(at: root)
        let metadata = try SQLiteSongUserMetadataStore(databaseURL: base.appendingPathComponent("State/metadata.sqlite"))
        let viewModel = ArchiveBrowserViewModel(context: context, songMetadataStore: metadata, runtime: MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.fixtureRootKey: root.path,
            MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
        ]))
        viewModel.scanSync()
        guard let mixed = viewModel.songs.first(where: { $0.originalFolderName == "Together" }),
              let ableton = mixed.projectVersions.first(where: { $0.format == .abletonLive }),
              let cubase = mixed.projectVersions.first(where: { $0.format == .cubase }) else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }
        viewModel.selectSong(mixed)
        try viewModel.openProjectVersion(ableton, for: mixed)
        let openedAbleton = viewModel.lastDryRunLog?.hasSuffix("/Song.als") == true
        try viewModel.openProjectVersion(cubase, for: mixed)
        let openedCubase = viewModel.lastDryRunLog?.hasSuffix("/Song.cpr") == true
        viewModel.setManualMainCPR(for: mixed, versionID: cubase.id)
        viewModel.scanSync()
        let main = viewModel.songs.first { $0.id == mixed.id }?.effectiveLatestProject
        viewModel.setSearchQuery("ableton", immediate: true)
        return SmokeRun(id: .abletonFlow, evidence: .abletonFlow(AbletonFlowEvidence(
            groupsCorrect: viewModel.songs.count == 2 && mixed.projectVersions.count == 2,
            openedAbleton: openedAbleton,
            openedCubase: openedCubase,
            manualMainPersists: main?.format == .cubase,
            searchFindsAbleton: viewModel.filteredSongs.count == 2,
            archiveUnchanged: before == (try snapshotArchiveTree(at: root))
        )))
    }
}
#endif
