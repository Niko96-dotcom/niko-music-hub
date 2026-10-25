import AppCore
import Combine
import Foundation
import NikoMusicCore

public enum DownloadState: Equatable {
    case idle
    case checkingURL
    case readyToDownload
    case downloading
    case completed
    case canceled
    /// yt-dlp cannot run: missing, outdated or broken. The card follows the status.
    case ytDlpUnavailable(HelperToolStatus)
    case failed(String)

    public static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checkingURL, .checkingURL): return true
        case (.readyToDownload, .readyToDownload): return true
        case (.downloading, .downloading): return true
        case (.completed, .completed): return true
        case (.canceled, .canceled): return true
        case let (.ytDlpUnavailable(lhsStatus), .ytDlpUnavailable(rhsStatus)): return lhsStatus == rhsStatus
        case let (.failed(lhsMsg), .failed(rhsMsg)): return lhsMsg == rhsMsg
        default: return false
        }
    }
}

@MainActor
public final class DownloaderViewModel: ObservableObject {
    @Published public var urlText: String = ""
    @Published public var formatSelection: DownloadFormatSelection
    @Published public var playlistMode: DownloadPlaylistMode = .single
    @Published public var detectedFileName: String?
    @Published public var downloadState: DownloadState = .idle
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var job: Job?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var downloadStartedAt: Date?
    @Published public private(set) var slowHintVisible = false
    /// "Converting audio…" etc. while yt-dlp post-processes; nil while downloading.
    @Published public private(set) var postProcessingStatus: String?
    @Published public private(set) var logEntries: [String] = []
    @Published public private(set) var outputURLs: [URL] = []

    public var showsDeterminateProgress: Bool {
        progress > 0
    }

    let context: ToolContext
    private let useCase: any DownloaderUseCaseRunning
    private let debounceDuration: Duration
    private var helperStatusObservation: AnyCancellable?
    private var observeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var downloadStartTask: Task<Void, Never>?
    private var progressFeedbackTask: Task<Void, Never>?
    private var stallMonitor: DownloadStallMonitor?
    private var validationGeneration: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    /// Token for the pending download start registered for quit (ADR-019). A
    /// finishing older start only unregisters when it still matches.
    private var downloadStartToken: UUID?
    private static let formatSelectionDefaultsKey = "downloader.formatSelection"

    public init(
        context: ToolContext,
        useCase: any DownloaderUseCaseRunning,
        formatSelection: DownloadFormatSelection? = nil,
        debounceDuration: Duration = .milliseconds(500)
    ) {
        self.context = context
        self.useCase = useCase
        self.debounceDuration = debounceDuration
        self.formatSelection = formatSelection ?? Self.loadPersistedFormatSelection(preferences: context.preferences)
        helperStatusObservation = context.helperHealth.$statuses
            .map { $0[.ytDlp] }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.helperStatusChanged(status) }
    }

    /// Set Up installed yt-dlp, or a path was saved: a URL that failed on
    /// yt-dlp is checked again once it is ready; a ready URL shows the problem.
    private func helperStatusChanged(_ status: HelperToolStatus?) {
        guard let status else { return }
        switch (status, downloadState) {
        case (.ready, .ytDlpUnavailable):
            retryHelperSetup()
        case (.ready, _):
            break
        case (_, .readyToDownload), (_, .ytDlpUnavailable):
            downloadState = .ytDlpUnavailable(status)
            statusMessage = nil
        default:
            break
        }
    }

    private static func loadPersistedFormatSelection(preferences: any PreferenceStore) -> DownloadFormatSelection {
        guard let data = preferences.data(forKey: formatSelectionDefaultsKey),
              let decoded = try? JSONDecoder().decode(DownloadFormatSelection.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    public func persistFormatSelection() {
        guard let data = try? JSONEncoder().encode(formatSelection) else { return }
        context.preferences.set(data, forKey: Self.formatSelectionDefaultsKey)
    }

    public func urlTextDidChange() {
        validationGeneration &+= 1
        let generation = validationGeneration
        let input = urlText
        let duration = debounceDuration
        let helperHealth = context.helperHealth
        let settingsStore = context.settingsStore
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard self?.beginURLCheck(input: input, generation: generation) == true else { return }

            let status: HelperToolStatus
            do {
                // Unreadable settings refuse the check instead of probing with defaults.
                _ = try settingsStore.loadSettings()
                status = await helperHealth.recheck(.ytDlp)
            } catch {
                guard !Task.isCancelled else { return }
                self?.context.diagnostics.scoped(to: .downloader).log(.error, "URL check could not read settings: \(error)")
                self?.applyURLCheckError(DownloadUseCaseError.settingsUnreadable, input: input, generation: generation)
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyURLCheckResult(status, input: input, generation: generation)
        }
    }

    private func beginURLCheck(input: String, generation: UInt64) -> Bool {
        guard isCurrentValidation(input: input, generation: generation),
              Self.validatedHTTPURL(input) != nil else {
            downloadState = .idle
            statusMessage = nil
            detectedFileName = nil
            return false
        }

        downloadState = .checkingURL
        statusMessage = DownloaderCopy.checkingURL
        return true
    }

    private func applyURLCheckResult(
        _ status: HelperToolStatus,
        input: String,
        generation: UInt64
    ) {
        guard isCurrentValidation(input: input, generation: generation),
              let url = Self.validatedHTTPURL(input) else { return }
        switch status {
        case .ready:
            downloadState = .readyToDownload
            statusMessage = DownloaderCopy.readyToDownload
            detectedFileName = DownloaderUseCase.fallbackJobTitle(for: url)
        case .missing, .outdated, .broken:
            // The check only runs `yt-dlp --version`, so this is a helper failure, not a URL failure.
            downloadState = .ytDlpUnavailable(status)
            statusMessage = nil
        }
    }

    private func applyURLCheckError(_ error: any Error, input: String, generation: UInt64) {
        guard isCurrentValidation(input: input, generation: generation) else { return }
        downloadState = .failed(error.localizedDescription)
        statusMessage = nil
    }

    private func isCurrentValidation(input: String, generation: UInt64) -> Bool {
        validationGeneration == generation && urlText == input
    }

    public func submitIfReady() {
        guard downloadState == .readyToDownload else { return }
        startDownload()
    }

    public func startDownload() {
        guard downloadState == .readyToDownload || downloadState == .canceled,
              let sourceURL = Self.validatedHTTPURL(urlText) else {
            return
        }

        let destination: ToolOutputDestination
        do {
            destination = try ToolOutputDestination.load(from: context.settingsStore)
        } catch {
            context.diagnostics.scoped(to: .downloader).log(.error, "Download start could not read settings: \(error)")
            downloadState = .failed(DownloaderCopy.settingsUnreadable)
            statusMessage = nil
            return
        }

        do {
            try destination.validate(destination.folder)
        } catch {
            context.diagnostics.scoped(to: .downloader).log(.error, "Download start failed: \(error.localizedDescription)")
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
            return
        }
        context.diagnostics.scoped(to: .downloader).log(.info, "Download started")

        let capturedFormatSelection = formatSelection
        let capturedPlaylistMode = playlistMode
        let options = DownloadJobOptions(
            sourceURL: sourceURL,
            outputDirectory: destination.folder,
            formatSelection: capturedFormatSelection,
            playlistMode: capturedPlaylistMode
        )

        logEntries = []
        progress = 0
        outputURLs = []
        errorMessage = nil
        job = nil
        persistFormatSelection()
        downloadState = .downloading
        statusMessage = DownloaderCopy.downloading
        beginDownloadProgressFeedback()

        downloadStartTask?.cancel()
        observeTask?.cancel()
        observationGeneration &+= 1
        let generation = observationGeneration
        let startToken = UUID()
        downloadStartToken = startToken
        let useCase = useCase
        let startedTask = Task { @MainActor [weak self] in
            // Every exit path clears the pending-start entry (token-guarded so
            // a late older start never clears a newer start's entry).
            defer { self?.clearPendingDownloadStart(matching: startToken) }
            do {
                let observedJob = try await useCase.simulateAndEnqueue(url: sourceURL, options: options)
                guard !Task.isCancelled else {
                    self?.context.jobRunner.cancelJob(id: observedJob.id)
                    return
                }
                self?.acceptStartedJob(
                    observedJob,
                    sourceURL: sourceURL,
                    outputDirectory: options.outputDirectory,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyStartError(error, generation: generation)
            }
        }
        downloadStartTask = startedTask
        // ADR-019: the title lookup runs before any runner job exists, so the
        // pending start registers as unlisted quit-blocking work until this
        // task finishes (the runner job then covers quit itself). The cancel
        // only cancels this start's task, which kills the lookup helper.
        context.jobStatusCenter.setExtraJob(
            sourceID: ShellJobExtraSourceID.downloadStart,
            status: ShellJobStatus(
                id: ShellJobExtraSourceID.downloadStart,
                title: DownloaderUseCase.fallbackJobTitle(for: sourceURL),
                activityVerb: DownloaderUseCase.activityVerb,
                sourceToolID: .downloader,
                blocksQuit: true,
                listed: false
            ),
            cancel: { startedTask.cancel() }
        )
    }

    /// Removes the pending-start quit entry, but only when `token` is still
    /// the latest start (a newer start replaced the entry).
    private func clearPendingDownloadStart(matching token: UUID) {
        guard downloadStartToken == token else { return }
        downloadStartToken = nil
        context.jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.downloadStart, status: nil)
    }

    private func acceptStartedJob(_ observedJob: Job, sourceURL: URL, outputDirectory: URL, generation: UInt64) {
        guard observationGeneration == generation, downloadState == .downloading else { return }
        job = observedJob
        if observedJob.title.hasPrefix(DownloaderUseCase.jobTitlePrefix) {
            let title = String(observedJob.title.dropFirst(DownloaderUseCase.jobTitlePrefix.count))
            if !title.isEmpty { detectedFileName = title }
        }
        observeJob(id: observedJob.id, sourceURL: sourceURL, outputDirectory: outputDirectory, generation: generation)
    }

    private func applyStartError(_ error: any Error, generation: UInt64) {
        guard observationGeneration == generation else { return }
        context.diagnostics.scoped(to: .downloader).log(.error, "Download start failed: \(error.localizedDescription)")
        if case let .ytDlpUnavailable(status)? = error as? DownloadUseCaseError {
            downloadState = .ytDlpUnavailable(status)
        } else {
            downloadState = .failed(error.localizedDescription)
        }
        statusMessage = nil
        endDownloadProgressFeedback()
    }

    private func observeJob(id: Job.ID, sourceURL: URL, outputDirectory: URL, generation: UInt64) {
        observeTask?.cancel()
        let jobRunner = context.jobRunner
        observeTask = Task { @MainActor [weak self] in
            for await observedJob in jobRunner.updates(for: id) {
                guard !Task.isCancelled else { return }
                guard self?.applyObservedJob(
                    observedJob,
                    id: id,
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    generation: generation
                ) == false else { return }
            }
        }
    }

    private func applyObservedJob(
        _ observedJob: Job,
        id: Job.ID,
        sourceURL: URL,
        outputDirectory: URL,
        generation: UInt64
    ) -> Bool {
        guard observationGeneration == generation, job?.id == id else { return true }
        let nextLogs = observedJob.logEntries.map(\.message)
        let progressChanged = observedJob.progress != progress
        let logsChanged = nextLogs != logEntries
        progress = observedJob.progress
        logEntries = nextLogs
        if progressChanged || logsChanged {
            let phase = logsChanged ? DownloadActivityPhase.latest(in: nextLogs) : nil
            stallMonitor?.recordActivity(phase: phase)
            if let phase {
                postProcessingStatus = phase.statusMessage
            }
            slowHintVisible = false
        }

        switch observedJob.state {
        case .completed:
            // Completed-path truthfulness: a completed job with no verified
            // contained outputs must fail rather than report Downloaded.
            // Outputs arrive as structured verified URLs; only the typed
            // outcome decides presentation, never log/message text.
            let handoff = handOffOutputsToInbox(
                candidateURLs: observedJob.outputFileURLs,
                sourceURL: sourceURL,
                outputDirectory: outputDirectory
            )
            guard !handoff.verified.isEmpty else {
                downloadState = .failed(
                    DownloadError.outputNotFound.errorDescription ?? "No output files found after download."
                )
                statusMessage = nil
                endDownloadProgressFeedback()
                return true
            }
            downloadState = .completed
            statusMessage = "Downloaded"
            endDownloadProgressFeedback()
            HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.downloadComplete)
            if let handoffFailure = handoff.firstFailure {
                errorMessage = DownloaderCopy.outputInboxHandoffWarning(handoffFailure)
            } else {
                errorMessage = nil
            }
            return true
        case .failed:
            // Typed policy: only `.downloadAlreadyExists` may present the
            // already-exists status, and only with verified outputs. Every
            // other failed job stays failed while still exposing verified
            // files. Presentation text never decides.
            if observedJob.failureReason == .downloadAlreadyExists {
                let handoff = handOffOutputsToInbox(
                    candidateURLs: observedJob.outputFileURLs,
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory
                )
                guard !handoff.verified.isEmpty else {
                    downloadState = .failed(observedJob.message)
                    statusMessage = nil
                    endDownloadProgressFeedback()
                    return true
                }
                if let handoffFailure = handoff.firstFailure {
                    downloadState = .failed(DownloaderCopy.outputInboxHandoffWarning(handoffFailure))
                    statusMessage = nil
                    errorMessage = nil
                    endDownloadProgressFeedback()
                    return true
                }
                // NMH-141 (TOOL-30): yt-dlp skipped because the file already
                // exists (`--no-overwrites` kept). Informational status, not a
                // fail and not an alert. Never overwrites the existing file.
                errorMessage = nil
                downloadState = .completed
                statusMessage = DownloaderCopy.alreadyExistsInInbox
                endDownloadProgressFeedback()
                HubAccessibilityAnnouncer.announce(DownloaderCopy.alreadyExistsInInbox)
                return true
            }
            if observedJob.failureReason == .downloaderHelperUnavailable {
                // The job only fails this way when yt-dlp is gone (`DownloaderUseCase`).
                downloadState = .ytDlpUnavailable(.missing)
                statusMessage = nil
                endDownloadProgressFeedback()
                return true
            }
            let handoff = handOffOutputsToInbox(
                candidateURLs: observedJob.outputFileURLs,
                sourceURL: sourceURL,
                outputDirectory: outputDirectory
            )
            if handoff.verified.isEmpty {
                downloadState = .failed(observedJob.message)
                statusMessage = nil
                endDownloadProgressFeedback()
                return true
            }
            if let handoffFailure = handoff.firstFailure {
                downloadState = .failed(DownloaderCopy.outputInboxHandoffWarning(handoffFailure))
            } else {
                downloadState = .failed(observedJob.message)
            }
            statusMessage = nil
            endDownloadProgressFeedback()
            return true
        case .canceled:
            downloadState = .canceled
            statusMessage = DownloaderCopy.downloadCanceledDetail
            errorMessage = nil
            endDownloadProgressFeedback()
            return true
        case .queued, .running:
            return false
        }
    }

    /// Single output-inbox handoff mechanism: verifies candidates (regular
    /// contained files in the captured output directory, never overwriting),
    /// attempts every verified output, updates outputURLs,
    /// logs failures, and returns the verified set plus the first failure.
    /// Caller policy stays distinct: completed downloads stay completed with
    /// a warning; failed handoffs report failed; partial playlists stay
    /// failed while exposing verified outputs. Metadata preserves the
    /// captured sourceURL (not subsequently edited input).
    private func handOffOutputsToInbox(
        candidateURLs: [URL],
        sourceURL: URL,
        outputDirectory: URL
    ) -> (verified: [URL], firstFailure: String?) {
        let verified = YtDlpDownloader.verifiedRegularContainedOutputs(candidateURLs, in: outputDirectory)
        outputURLs = verified

        var firstFailure: String?
        for outputURL in verified {
            let item = OutputInboxItem(
                fileURL: outputURL,
                sourceToolID: .downloader,
                status: .available,
                metadata: ["dlSourceURL": sourceURL.absoluteString]
            )
            do {
                try context.outputInboxStore.addItem(item)
            } catch {
                if firstFailure == nil {
                    firstFailure = error.localizedDescription
                }
            }
        }

        if let firstFailure {
            context.diagnostics.scoped(to: .downloader).log(.error, "Download inbox handoff failed: \(firstFailure)")
        }
        return (verified, firstFailure)
    }

    public func cancelDownload() {
        guard downloadState == .downloading else { return }
        if let id = job?.id {
            context.jobRunner.cancelJob(id: id)
            return
        }
        observationGeneration &+= 1
        downloadStartTask?.cancel()
        downloadStartTask = nil
        downloadState = .canceled
        statusMessage = DownloaderCopy.downloadCanceledDetail
        errorMessage = nil
        endDownloadProgressFeedback()
    }

    public func retryAfterFailure() {
        guard Self.validatedHTTPURL(urlText) != nil else {
            downloadState = .idle
            return
        }
        downloadState = .readyToDownload
        statusMessage = DownloaderCopy.readyToDownload
    }

    public func retryHelperSetup() {
        guard Self.validatedHTTPURL(urlText) != nil else {
            downloadState = .idle
            return
        }
        urlTextDidChange()
    }

    public func chooseYtDlpPath() {
        guard let url = context.fileActions.chooseExecutable(prompt: "Choose yt-dlp") else { return }
        do {
            try context.settingsStore.updateSettings { settings in
                settings.helperTools.ytDlp = url
            }
            retryHelperSetup()
        } catch {
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    public func clearInput() {
        validationGeneration &+= 1
        observationGeneration &+= 1
        cancelOutstandingTasks()
        urlText = ""
        detectedFileName = nil
        downloadState = .idle
        statusMessage = nil
        errorMessage = nil
        job = nil
        progress = 0
        logEntries = []
        outputURLs = []
        endDownloadProgressFeedback()
    }

    deinit {
        debounceTask?.cancel()
        observeTask?.cancel()
        downloadStartTask?.cancel()
        progressFeedbackTask?.cancel()
        context.jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.downloadStart, status: nil)
    }

    static func validatedHTTPURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }

    private func cancelOutstandingTasks() {
        debounceTask?.cancel()
        observeTask?.cancel()
        downloadStartTask?.cancel()
        progressFeedbackTask?.cancel()
        debounceTask = nil
        observeTask = nil
        downloadStartTask = nil
        progressFeedbackTask = nil
    }

    private func beginDownloadProgressFeedback() {
        let monitor = DownloadStallMonitor()
        monitor.recordActivity()
        stallMonitor = monitor
        downloadStartedAt = Date()
        slowHintVisible = false
        postProcessingStatus = nil
        progressFeedbackTask?.cancel()
        progressFeedbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, self.downloadState == .downloading else { return }
                if self.stallMonitor?.checkSlowHint() == true {
                    self.slowHintVisible = true
                }
            }
        }
    }

    private func endDownloadProgressFeedback() {
        progressFeedbackTask?.cancel()
        progressFeedbackTask = nil
        stallMonitor = nil
        downloadStartedAt = nil
        slowHintVisible = false
        postProcessingStatus = nil
    }
}
