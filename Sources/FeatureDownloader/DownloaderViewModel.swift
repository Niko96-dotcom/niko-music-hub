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
    case failed(String)

    public static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checkingURL, .checkingURL): return true
        case (.readyToDownload, .readyToDownload): return true
        case (.downloading, .downloading): return true
        case (.completed, .completed): return true
        case (.canceled, .canceled): return true
        case let (.failed(lhsMsg), .failed(rhsMsg)): return lhsMsg == rhsMsg
        default: return false
        }
    }
}

@MainActor
public final class DownloaderViewModel: ObservableObject, @unchecked Sendable {
    public static let toolID = ToolFeatureID("downloader")
    /// How many finished downloads stay visible on the tool page (full history lives in the Output Inbox).
    static let recentDownloadsLimit = 5

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
    @Published public private(set) var logEntries: [String] = []
    @Published public private(set) var outputURLs: [URL] = []
    @Published public private(set) var recentDownloads: [OutputInboxItem] = []

    public var showsDeterminateProgress: Bool {
        progress > 0
    }

    public func elapsedCaption(at now: Date = Date()) -> String {
        Self.formatElapsed(since: downloadStartedAt, now: now)
    }

    static func formatElapsed(since start: Date?, now: Date) -> String {
        let interval = start.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let totalSeconds = Int(interval)
        return String(format: "Elapsed %d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private let context: ToolContext
    private let useCase: any DownloaderUseCaseRunning
    private let healthChecker: YtDlpHealthChecker
    private let debounceDuration: Duration
    private var observeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var downloadStartTask: Task<Void, Never>?
    private var inboxObservationTask: Task<Void, Never>?
    private var progressFeedbackTask: Task<Void, Never>?
    private var stallMonitor: DownloadStallMonitor?
    private var validationGeneration: UInt64 = 0
    private var observationGeneration: UInt64 = 0
    private static let formatSelectionDefaultsKey = "downloader.formatSelection"

    public init(
        context: ToolContext,
        useCase: any DownloaderUseCaseRunning,
        healthChecker: YtDlpHealthChecker = YtDlpHealthChecker(),
        formatSelection: DownloadFormatSelection? = nil,
        debounceDuration: Duration = .milliseconds(500)
    ) {
        self.context = context
        self.useCase = useCase
        self.healthChecker = healthChecker
        self.debounceDuration = debounceDuration
        self.formatSelection = formatSelection ?? Self.loadPersistedFormatSelection(preferences: context.preferences)
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
        let healthChecker = healthChecker
        let settingsStore = context.settingsStore
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard self?.beginURLCheck(input: input, generation: generation) == true else { return }

            let availability: YtDlpAvailability
            do {
                let settings = try settingsStore.loadSettings()
                availability = await healthChecker.availability(settings: settings.helperTools)
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyURLCheckError(error, input: input, generation: generation)
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyURLCheckResult(availability, input: input, generation: generation)
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
        _ availability: YtDlpAvailability,
        input: String,
        generation: UInt64
    ) {
        guard isCurrentValidation(input: input, generation: generation),
              let url = Self.validatedHTTPURL(input) else { return }
        switch availability {
        case .available:
            downloadState = .readyToDownload
            statusMessage = DownloaderCopy.readyToDownload
            detectedFileName = url.lastPathComponent
        case .missing:
            downloadState = .failed(DownloaderCopy.missingYtDlp)
            statusMessage = nil
        case .unusable:
            downloadState = .failed(DownloaderCopy.unsupportedURL)
            statusMessage = nil
        case let .outdated(current, minimumExpected):
            downloadState = .failed(DownloaderCopy.outdatedYtDlp(current: current, minimumExpected: minimumExpected))
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

        let settings: AppSettings
        do {
            settings = try context.settingsStore.loadSettings()
        } catch {
            context.diagnostics.scoped(to: .downloader).log(.error, "Download start failed: \(error.localizedDescription)")
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
            return
        }

        do {
            try OutputWriteGuard().validateCanWriteOutput(
                to: settings.outputFolder.url,
                archiveRoots: settings.archiveRoots.map(\.url)
            )
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
            outputDirectory: settings.outputFolder.url,
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
        let useCase = useCase
        downloadStartTask = Task { @MainActor [weak self] in
            do {
                let observedJob = try await useCase.simulateAndEnqueue(url: sourceURL, options: options)
                guard !Task.isCancelled else {
                    self?.context.jobRunner.cancelJob(id: observedJob.id)
                    return
                }
                self?.acceptStartedJob(observedJob, sourceURL: sourceURL, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyStartError(error, generation: generation)
            }
        }
    }

    private func acceptStartedJob(_ observedJob: Job, sourceURL: URL, generation: UInt64) {
        guard observationGeneration == generation, downloadState == .downloading else { return }
        job = observedJob
        observeJob(id: observedJob.id, sourceURL: sourceURL, generation: generation)
    }

    private func applyStartError(_ error: any Error, generation: UInt64) {
        guard observationGeneration == generation else { return }
        context.diagnostics.scoped(to: .downloader).log(.error, "Download start failed: \(error.localizedDescription)")
        downloadState = .failed(error.localizedDescription)
        statusMessage = nil
        endDownloadProgressFeedback()
    }

    private func observeJob(id: Job.ID, sourceURL: URL, generation: UInt64) {
        observeTask?.cancel()
        let jobRunner = context.jobRunner
        observeTask = Task { @MainActor [weak self] in
            for await observedJob in jobRunner.updates(for: id) {
                guard !Task.isCancelled else { return }
                guard self?.applyObservedJob(
                    observedJob,
                    id: id,
                    sourceURL: sourceURL,
                    generation: generation
                ) == false else { return }
            }
        }
    }

    private func applyObservedJob(
        _ observedJob: Job,
        id: Job.ID,
        sourceURL: URL,
        generation: UInt64
    ) -> Bool {
        guard observationGeneration == generation, job?.id == id else { return true }
        let nextLogs = observedJob.logEntries.map(\.message)
        let progressChanged = observedJob.progress != progress
        let logsChanged = nextLogs != logEntries
        progress = observedJob.progress
        logEntries = nextLogs
        if progressChanged || logsChanged {
            stallMonitor?.recordActivity()
            slowHintVisible = false
        }

        switch observedJob.state {
        case .completed:
            downloadState = .completed
            statusMessage = "Downloaded"
            endDownloadProgressFeedback()
            HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.downloadComplete)
            addToInbox(job: observedJob, sourceURL: sourceURL)
            return true
        case .failed:
            if Self.isAlreadyDownloadedSkip(logEntries: nextLogs, message: observedJob.message) {
                // NMH-141 (TOOL-30): yt-dlp skipped because the file already
                // exists (`--no-overwrites` kept). Informational status, not a
                // fail and not an alert. Never overwrites the existing file.
                downloadState = .completed
                statusMessage = DownloaderCopy.alreadyExistsInInbox
                endDownloadProgressFeedback()
                HubAccessibilityAnnouncer.announce(DownloaderCopy.alreadyExistsInInbox)
                loadRecentDownloads()
                return true
            }
            downloadState = .failed(observedJob.message)
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

    private func addToInbox(job: Job, sourceURL: URL) {
        let foundURLs = job.outputFileURLs.filter {
            Self.regularFileExists(at: $0)
        }

        self.outputURLs = foundURLs

        var handoffFailures: [String] = []
        for outputURL in foundURLs {
            let item = OutputInboxItem(
                fileURL: outputURL,
                sourceToolID: Self.toolID,
                status: .available,
                metadata: ["dlSourceURL": sourceURL.absoluteString]
            )
            do {
                try context.outputInboxStore.addItem(item)
            } catch {
                handoffFailures.append(error.localizedDescription)
            }
        }

        if let firstFailure = handoffFailures.first {
            context.diagnostics.scoped(to: .downloader).log(.error, "Download inbox handoff failed: \(firstFailure)")
            errorMessage = DownloaderCopy.outputInboxHandoffWarning(firstFailure)
        } else {
            errorMessage = nil
        }
        loadRecentDownloads()
    }

    public func onAppear() {
        loadRecentDownloads()
        guard inboxObservationTask == nil else { return }
        inboxObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .outputInboxDidChange) {
                guard !Task.isCancelled else { return }
                self?.loadRecentDownloads()
            }
        }
    }

    public func loadRecentDownloads() {
        let items = (try? context.outputInboxStore.listItems()) ?? []
        recentDownloads = Array(
            items
                .filter { $0.sourceToolID == Self.toolID }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(Self.recentDownloadsLimit)
        )
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
        inboxObservationTask?.cancel()
        progressFeedbackTask?.cancel()
    }

    public var outputFolder: URL {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        return settings.outputFolder.url
    }

    private static func regularFileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
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

    /// NMH-141 (TOOL-30): true when the failed job's logs or message carry
    /// yt-dlp's already-downloaded marker, meaning `--no-overwrites` skipped
    /// an existing file rather than a network failure occurring.
    static func isAlreadyDownloadedSkip(logEntries: [String], message: String) -> Bool {
        if YtDlpDownloader.containsAlreadyDownloadedMarker(message) { return true }
        return logEntries.contains { YtDlpDownloader.containsAlreadyDownloadedMarker($0) }
    }

    private func cancelOutstandingTasks() {
        debounceTask?.cancel()
        observeTask?.cancel()
        downloadStartTask?.cancel()
        inboxObservationTask?.cancel()
        progressFeedbackTask?.cancel()
        debounceTask = nil
        observeTask = nil
        downloadStartTask = nil
        inboxObservationTask = nil
        progressFeedbackTask = nil
    }

    private func beginDownloadProgressFeedback() {
        let monitor = DownloadStallMonitor()
        monitor.recordActivity()
        stallMonitor = monitor
        downloadStartedAt = Date()
        slowHintVisible = false
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
    }
}
