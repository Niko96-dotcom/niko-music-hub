import AppCore
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// NMH-066: which intake owns the filled primary action.
public enum StemPrimaryIntake: Equatable, Sendable {
    case file
    case youtube
}

@MainActor
public final class StemSeparationViewModel: ObservableObject, @unchecked Sendable {
    @Published public var selectedPreset: StemSeparationPreset = StemSeparationPreset.defaultPreset
    @Published public var outputFolderURL: URL = StoredFolderLocation.defaultOutputFolder
    @Published public var droppedFileURL: URL?
    @Published public var youtubeURLText = ""
    @Published public private(set) var isRunning = false
    @Published public private(set) var progress = 0.0
    @Published public private(set) var statusMessage = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var helperNeedsSetup = false
    @Published public private(set) var results: [OutputInboxItem] = []

    public let supportedPresets = StemSeparationPreset.allCases

    private let context: ToolContext
    private let service: StemSeparationService
    private let youtubeWorkflow: YouTubeStemSeparationWorkflow?
    private let healthChecker: DemucsMLXHealthChecker
    private var jobObservationTask: Task<Void, Never>?
    private var inboxObservationTask: Task<Void, Never>?
    private var helperToolsObservation: AnyCancellable?
    private(set) var currentJobID: Job.ID?

    public init(
        context: ToolContext,
        service: StemSeparationService,
        youtubeWorkflow: YouTubeStemSeparationWorkflow? = nil,
        healthChecker: DemucsMLXHealthChecker = DemucsMLXHealthChecker()
    ) {
        self.context = context
        self.service = service
        self.youtubeWorkflow = youtubeWorkflow
        self.healthChecker = healthChecker
        loadSettings()
    }

    deinit {
        jobObservationTask?.cancel()
        inboxObservationTask?.cancel()
    }

    public var canStart: Bool {
        !isRunning && droppedFileURL != nil && !helperNeedsSetup
    }

    /// Helper-missing recovery: open the helper-tool Set Up sheet.
    public func openHubSettingsHelpers() {
        context.router.requestHelperToolSetup()
    }

    public var canStartYouTube: Bool {
        !isRunning && normalizedYouTubeURL() != nil && youtubeWorkflow != nil
    }

    public var canCancel: Bool {
        isRunning && currentJobID != nil
    }

    /// NMH-066: exclusive primary intake. A parsable YouTube URL wins over a
    /// dropped file so Stems never shows two filled primaries.
    public var primaryIntake: StemPrimaryIntake {
        normalizedYouTubeURL() != nil ? .youtube : .file
    }

    public func handleDrop(urls: [URL]) -> Bool {
        guard let first = urls.first else { return false }
        let isAudio = Self.allowedDropExtensions.contains(first.pathExtension.lowercased())
        guard isAudio else {
            errorMessage = "Please drop an audio file."
            return false
        }
        droppedFileURL = first
        errorMessage = nil
        statusMessage = "Ready: \(first.lastPathComponent)"
        return true
    }

    // NMH-061: shared allow-list for drop targeting and unit tests.
    nonisolated public static let allowedDropExtensions: Set<String> = ["wav", "aiff", "aif", "mp3", "m4a", "flac"]

    /// NMH-061: URL-based acceptance matching `handleDrop` for unit tests.
    nonisolated public func canAcceptDrop(urls: [URL]) -> Bool {
        guard let first = urls.first else { return false }
        return Self.allowedDropExtensions.contains(first.pathExtension.lowercased())
    }

    /// NMH-061: synchronous targeting check. True when any provider conforms to
    /// an audio UTI or vends a fileURL whose extension is in the allow-list.
    nonisolated public func canAcceptDrop(info: DropInfo) -> Bool {
        var audioTypes: [UTType] = [.audio, .wav, .aiff, .mp3, .mpeg4Audio]
        if let flac = UTType(filenameExtension: "flac") {
            audioTypes.append(flac)
        }
        if let aif = UTType(filenameExtension: "aif") {
            audioTypes.append(aif)
        }
        if let m4a = UTType(filenameExtension: "m4a") {
            audioTypes.append(m4a)
        }
        if audioTypes.contains(where: { info.hasItemsConforming(to: [$0]) }) {
            return true
        }
        for provider in info.itemProviders(for: [.fileURL]) {
            if let name = provider.suggestedName, !name.isEmpty {
                let ext = (name as NSString).pathExtension.lowercased()
                if Self.allowedDropExtensions.contains(ext) {
                    return true
                }
            }
            for identifier in provider.registeredTypeIdentifiers {
                guard let type = UTType(identifier) else { continue }
                if audioTypes.contains(where: { type.conforms(to: $0) }) {
                    return true
                }
            }
        }
        return false
    }

    /// NMH-061: delegate drop entry. Rejects non-audio with the existing error copy.
    public func performDrop(info: DropInfo) -> Bool {
        guard canAcceptDrop(info: info) else {
            errorMessage = "Please drop an audio file."
            return false
        }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            errorMessage = "Please drop an audio file."
            return false
        }
        Task { @MainActor [weak self] in
            var urls: [URL] = []
            for provider in providers {
                guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) else { continue }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data {
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    } else if let string = String(data: data, encoding: .utf8),
                              let url = URL(string: string) {
                        urls.append(url)
                    }
                }
            }
            guard !urls.isEmpty else {
                self?.errorMessage = "Please drop an audio file."
                return
            }
            _ = self?.handleDrop(urls: urls)
        }
        return true
    }

    public func selectFile() {
        guard let url = context.fileActions.chooseAudioFile(prompt: "Choose Audio File") else { return }
        _ = handleDrop(urls: [url])
    }

    public func pickOutputFolder() {
        guard let url = context.fileActions.chooseOutputFolder() else { return }
        outputFolderURL = url
        saveOutputFolder(url)
    }

    public func startSeparation() {
        guard let inputURL = droppedFileURL else { return }
        guard !isRunning else { return }

        loadSettings()

        let request = StemSeparationRequest(
            inputURL: inputURL,
            outputRootURL: outputFolderURL,
            preset: selectedPreset,
            title: nil
        )

        isRunning = true
        progress = 0.0
        errorMessage = nil
        statusMessage = "Starting \(selectedPreset.displayName)…"

        let job = service.startJob(request: request)
        currentJobID = job.id
        observe(job: job)
    }

    public func startYouTubeSeparation() {
        guard !isRunning else { return }
        guard let sourceURL = normalizedYouTubeURL() else {
            errorMessage = "Paste a valid YouTube URL."
            return
        }
        guard let youtubeWorkflow else {
            errorMessage = "YouTube to stems is unavailable."
            return
        }

        loadSettings()

        let request = YouTubeStemSeparationRequest(
            sourceURL: sourceURL,
            outputRootURL: outputFolderURL,
            preset: selectedPreset
        )

        isRunning = true
        progress = 0.0
        errorMessage = nil
        statusMessage = "Downloading audio…"

        let job = youtubeWorkflow.startJob(request: request)
        currentJobID = job.id
        observe(job: job)
    }

    public func cancelSeparation() {
        guard let id = currentJobID else { return }
        context.jobRunner.cancelJob(id: id)
    }

    public func clearSelection() {
        droppedFileURL = nil
        statusMessage = ""
    }

    public func clearYouTubeURL() {
        youtubeURLText = ""
        if droppedFileURL == nil {
            statusMessage = ""
        }
    }

    public func loadResults() {
        do {
            results = try context.outputInboxStore.listItems()
                .filter { $0.sourceToolID == StemSeparationService.toolID }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            diagnosticsError(error)
        }
    }

    public func reveal(item: OutputInboxItem) {
        context.fileActions.revealInFinder(item.fileURL)
    }

    public func dragURL(for item: OutputInboxItem) -> URL? {
        OutputHandoff.dragFileURL(for: item)
    }

    public func onAppear() {
        loadResults()
        refreshHelperHealth()
        if helperToolsObservation == nil {
            helperToolsObservation = context.router.$helperToolsChangeCount
                .dropFirst()
                .sink { [weak self] _ in self?.refreshHelperHealth() }
        }
        guard inboxObservationTask == nil else { return }
        inboxObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .outputInboxDidChange) {
                guard !Task.isCancelled else { return }
                self?.loadResults()
            }
        }
    }

    public func chooseHelperPath() {
        guard let url = context.fileActions.chooseExecutable(prompt: "Choose demucs-mlx") else { return }
        do {
            try context.settingsStore.updateSettings { settings in
                settings.helperTools.demucsMlx = url
            }
            refreshHelperHealth()
        } catch {
            diagnosticsError(error)
        }
    }

    public func refreshHelperHealth() {
        Task { @MainActor [weak self] in
            await self?.runHelperHealthCheck()
        }
    }

    private func runHelperHealthCheck() async {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let health = await healthChecker.availability(settings: settings.helperTools)
        switch health {
        case .missing:
            helperNeedsSetup = true
            errorMessage = StemSeparationHelperCopy.missingBody
        case .ready:
            if helperNeedsSetup || errorMessage == StemSeparationHelperCopy.missingBody {
                errorMessage = nil
            }
            helperNeedsSetup = false
        case let .unusable(message):
            helperNeedsSetup = true
            errorMessage = Self.startFailureMessage(from: message)
        case .modelCacheMissing:
            helperNeedsSetup = true
            errorMessage = StemSeparationHelperCopy.missingBody
        }
    }

    static func startFailureMessage(from message: String) -> String {
        let firstLine = message
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = (firstLine?.isEmpty == false ? firstLine! : message.trimmingCharacters(in: .whitespacesAndNewlines))
        let limited = String(trimmed.prefix(200))
        return "demucs-mlx could not start: \(limited)"
    }

    private func observe(job: Job) {
        jobObservationTask?.cancel()
        let jobRunner = context.jobRunner
        jobObservationTask = Task { @MainActor [weak self] in
            for await current in jobRunner.updates(for: job.id) {
                guard !Task.isCancelled else { return }
                guard self?.applyObservedJob(current, expectedID: job.id) == false else { return }
            }
        }
    }

    private func applyObservedJob(_ current: Job, expectedID: Job.ID) -> Bool {
        guard currentJobID == expectedID else { return true }
        progress = current.progress
        if !current.message.isEmpty {
            statusMessage = current.message
        }
        switch current.state {
        case .completed:
            finish(message: "Separation complete.")
            loadResults()
            return true
        case .failed:
            finish(message: current.message, error: current.message)
            if current.message == StemSeparationHelperCopy.missingBody {
                helperNeedsSetup = true
            }
            return true
        case .canceled:
            finish(message: "Canceled.")
            return true
        case .queued, .running:
            return false
        }
    }

    private func finish(message: String, error: String? = nil) {
        isRunning = false
        currentJobID = nil
        statusMessage = message
        errorMessage = error
    }

    private func loadSettings() {
        do {
            let settings = try context.settingsStore.loadSettings()
            outputFolderURL = settings.outputFolder.url
        } catch {
            diagnosticsError(error)
        }
    }

    private func saveOutputFolder(_ url: URL) {
        do {
            try context.settingsStore.updateSettings { settings in
                settings.outputFolder = StoredFolderLocation(url: url)
            }
        } catch {
            diagnosticsError(error)
        }
    }

    private func normalizedYouTubeURL() -> URL? {
        let trimmed = youtubeURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              Self.isApprovedYouTubeHost(host) else {
            return nil
        }
        return url
    }

    static func isApprovedYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
            || host.hasSuffix(".youtu.be")
    }

    private func diagnosticsError(_ error: Error) {
        statusMessage = error.localizedDescription
        context.diagnostics.scoped(to: .stemSeparation).log(.error, "Stem separation failed: \(error.localizedDescription)")
    }
}
