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
    private let useCase: any DownloaderUseCaseRunning
    private let jobFactory: DownloaderJobFactory
    private let healthChecker: YtDlpHealthChecker
    private var observeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let formatSelectionDefaultsKey = "downloader.formatSelection"

    public init(
        context: ToolContext,
        useCase: any DownloaderUseCaseRunning,
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
                downloadState = .failed(DownloaderCopy.outdatedYtDlp(current: current, minimumExpected: minimumExpected))
                statusMessage = nil
            }
        } catch {
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    public func startDownload() {
        guard case .readyToDownload = downloadState,
              let sourceURL = URL(string: urlText) else {
            return
        }

        let settings: AppSettings
        do {
            settings = try context.settingsStore.loadSettings()
        } catch {
            downloadState = .failed(error.localizedDescription)
            statusMessage = nil
            return
        }

        let capturedFormatSelection = formatSelection
        let options = jobFactory.makeJobOptions(
            sourceURL: sourceURL,
            outputDirectory: settings.outputFolder.url,
            formatSelection: capturedFormatSelection
        )

        logEntries = []
        progress = 0
        outputURLs = []
        errorMessage = nil
        job = nil
        persistFormatSelection()
        downloadState = .downloading
        statusMessage = DownloaderCopy.downloading

        Task { @MainActor in
            do {
                let observedJob = try await useCase.simulateAndEnqueue(url: sourceURL, options: options)
                self.job = observedJob
                observeJob(id: observedJob.id, sourceURL: sourceURL)
            } catch {
                downloadState = .failed(error.localizedDescription)
                statusMessage = nil
            }
        }
    }

    private func observeJob(id: Job.ID, sourceURL: URL) {
        observeTask?.cancel()
        observeTask = Task { @MainActor in
            while let job = context.jobRunner.job(id: id) {
                self.progress = job.progress
                self.logEntries = job.logEntries.map(\.message)

                if job.state == .completed {
                    self.downloadState = .completed
                    self.statusMessage = "Downloaded"
                    await self.addToInbox(job: job, sourceURL: sourceURL)
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

    private func addToInbox(job: Job, sourceURL: URL) async {
        let foundURLs = job.outputFileURLs.filter {
            Self.regularFileExists(at: $0)
        }

        self.outputURLs = foundURLs

        var handoffFailures: [String] = []
        for outputURL in foundURLs {
            let item = OutputInboxItem(
                fileURL: outputURL,
                sourceToolID: ToolFeatureID("downloader"),
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
            errorMessage = DownloaderCopy.outputInboxHandoffWarning(firstFailure)
        } else {
            errorMessage = nil
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

    private static func regularFileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
}
