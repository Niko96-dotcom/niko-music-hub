import AppCore
import Combine
import Foundation
import SwiftUI

@MainActor
public final class StemSeparationViewModel: ObservableObject, @unchecked Sendable {
    @Published public var selectedPreset: StemSeparationPreset = StemSeparationPreset.defaultPreset
    @Published public var outputFolderURL: URL = StoredFolderLocation.defaultOutputFolder
    @Published public var droppedFileURL: URL?
    @Published public var youtubeURLText = ""
    @Published public private(set) var isRunning = false
    @Published public private(set) var progress = 0.0
    @Published public private(set) var statusMessage = "Drop an audio file to start."
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
        !isRunning && droppedFileURL != nil
    }

    public var canStartYouTube: Bool {
        !isRunning && normalizedYouTubeURL() != nil && youtubeWorkflow != nil
    }

    public var canCancel: Bool {
        isRunning && currentJobID != nil
    }

    public func handleDrop(urls: [URL]) -> Bool {
        guard let first = urls.first else { return false }
        let isAudio = ["wav", "aiff", "aif", "mp3", "m4a", "flac"].contains(first.pathExtension.lowercased())
        guard isAudio else {
            errorMessage = "Please drop an audio file."
            return false
        }
        droppedFileURL = first
        errorMessage = nil
        statusMessage = "Ready: \(first.lastPathComponent)"
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
        statusMessage = "Starting \(selectedPreset.displayName)..."

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
        statusMessage = "Downloading audio..."

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
        statusMessage = "Drop an audio file to start."
    }

    public func clearYouTubeURL() {
        youtubeURLText = ""
        if droppedFileURL == nil {
            statusMessage = "Drop an audio file to start."
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
        case .unusable, .modelCacheMissing:
            helperNeedsSetup = true
            errorMessage = StemSeparationHelperCopy.missingBody
        }
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
        context.diagnostics.log(.error, "StemSeparationViewModel: \(error.localizedDescription)")
    }
}
