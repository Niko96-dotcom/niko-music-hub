import AppCore
import Combine
import Foundation

public enum DownloadState: Equatable {
    case idle
    case checkingURL
    case readyToDownload
    case downloading
    case completed
    case failed(String)

    public static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checkingURL, .checkingURL): return true
        case (.readyToDownload, .readyToDownload): return true
        case (.downloading, .downloading): return true
        case (.completed, .completed): return true
        case let (.failed(lhsMsg), .failed(rhsMsg)): return lhsMsg == rhsMsg
        default: return false
        }
    }
}

@MainActor
public final class DownloaderViewModel: ObservableObject, @unchecked Sendable {
    @Published public var urlText: String = ""
    @Published public var formatSelection: DownloadFormatSelection
    @Published public var detectedFileName: String?
    @Published public var downloadState: DownloadState = .idle
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var job: Job?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var logEntries: [String] = []
    @Published public private(set) var outputURLs: [URL] = []

    private let context: ToolContext
    private let useCase: DownloaderUseCase
    private let jobFactory: DownloaderJobFactory
    private let healthChecker: YtDlpHealthChecker
    private var observeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let formatSelectionDefaultsKey = "downloader.formatSelection"

    public init(
        context: ToolContext,
        useCase: DownloaderUseCase,
        healthChecker: YtDlpHealthChecker = YtDlpHealthChecker(),
        jobFactory: DownloaderJobFactory = DownloaderJobFactory(),
        formatSelection: DownloadFormatSelection? = nil
    ) {
        self.context = context
        self.useCase = useCase
        self.healthChecker = healthChecker
        self.jobFactory = jobFactory
        self.formatSelection = formatSelection ?? Self.loadPersistedFormatSelection()
    }

    private static func loadPersistedFormatSelection() -> DownloadFormatSelection {
        guard let data = UserDefaults.standard.data(forKey: "downloader.formatSelection"),
              let decoded = try? JSONDecoder().decode(DownloadFormatSelection.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    public func persistFormatSelection() {
        guard let data = try? JSONEncoder().encode(formatSelection) else { return }
        UserDefaults.standard.set(data, forKey: formatSelectionDefaultsKey)
    }

    public func urlTextDidChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await checkURL()
        }
    }

    private func checkURL() async {
        guard let url = URL(string: urlText), urlText.hasPrefix("http") else {
            downloadState = .idle
            statusMessage = nil
            detectedFileName = nil
            return
        }

        downloadState = .checkingURL
        statusMessage = DownloaderCopy.checkingURL

        do {
            let settings = try context.settingsStore.loadSettings()
            let availability = await healthChecker.availability(settings: settings.helperTools)
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
                downloadState = .failed("yt-dlp version \(current) is outdated. Expected \(minimumExpected) or higher.")
                statusMessage = nil
            }
        } catch {
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    public func startDownload() {
        guard case .readyToDownload = downloadState,
              let url = URL(string: urlText) else {
            return
        }

        logEntries = []
        progress = 0

        Task {
            do {
                let settings = try context.settingsStore.loadSettings()
                persistFormatSelection()
                let options = jobFactory.makeJobOptions(
                    sourceURL: url,
                    outputDirectory: settings.outputFolder.url,
                    formatSelection: formatSelection
                )

                downloadState = .downloading
                statusMessage = "Downloading..."
                let observedJob = try await useCase.simulateAndEnqueue(url: url, options: options)
                self.job = observedJob
                observeJob(id: observedJob.id)
            } catch {
                downloadState = .failed(error.localizedDescription)
                statusMessage = nil
            }
        }
    }

    private func observeJob(id: Job.ID) {
        observeTask?.cancel()
        observeTask = Task { @MainActor in
            while let job = context.jobRunner.job(id: id) {
                self.progress = job.progress
                self.logEntries = job.logEntries.map(\.message)

                if job.state == .completed {
                    self.downloadState = .completed
                    self.statusMessage = "Downloaded"
                    await self.addToInbox(job: job, sourceURLString: self.urlText)
                    break
                } else if job.state == .failed {
                    self.downloadState = .failed(job.message)
                    self.statusMessage = nil
                    break
                } else if job.state == .canceled {
                    self.downloadState = .failed("Download was cancelled.")
                    self.statusMessage = nil
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func addToInbox(job: Job, sourceURLString: String) async {
        guard let sourceURL = URL(string: sourceURLString) else { return }

        var foundURLs: [URL] = []
        for entry in job.logEntries {
            let msg = entry.message
            if msg.contains("[download] Destination:") {
                let pathPart = msg.components(separatedBy: "Destination:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                let url = URL(fileURLWithPath: pathPart)
                if FileManager.default.fileExists(atPath: url.path) {
                    foundURLs.append(url)
                }
            }
        }

        self.outputURLs = foundURLs

        for outputURL in foundURLs {
            let item = OutputInboxItem(
                fileURL: outputURL,
                sourceToolID: ToolFeatureID("downloader"),
                status: .available,
                metadata: ["dlSourceURL": sourceURL.absoluteString]
            )
            try? context.outputInboxStore.addItem(item)
        }
    }

    public func retryAfterFailure() {
        guard urlText.hasPrefix("http"), URL(string: urlText) != nil else {
            downloadState = .idle
            return
        }
        downloadState = .readyToDownload
        statusMessage = DownloaderCopy.readyToDownload
    }

    public func clearInput() {
        urlText = ""
        detectedFileName = nil
        downloadState = .idle
        statusMessage = nil
        errorMessage = nil
        job = nil
        progress = 0
        logEntries = []
        outputURLs = []
        observeTask?.cancel()
        debounceTask?.cancel()
    }

    public var outputFolder: URL {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        return settings.outputFolder.url
    }
}