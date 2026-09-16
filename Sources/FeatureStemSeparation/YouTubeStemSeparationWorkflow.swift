import AppCore
import FeatureDownloader
import Foundation

public protocol YouTubeAudioDownloading: Sendable {
    func downloadAudio(
        from sourceURL: URL,
        to outputDirectory: URL,
        progress: JobProgress
    ) async throws -> URL
}

public struct YtDlpYouTubeAudioDownloader: YouTubeAudioDownloading {
    private let useCase: DownloaderUseCase

    public init(useCase: DownloaderUseCase) {
        self.useCase = useCase
    }

    public func downloadAudio(
        from sourceURL: URL,
        to outputDirectory: URL,
        progress: JobProgress
    ) async throws -> URL {
        let options = DownloadJobOptions(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            formatSelection: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .wav),
            retries: 3
        )
        let outputURLs = try await useCase.download(url: sourceURL, options: options, progress: progress)
        guard let audioURL = outputURLs.first(where: Self.isSupportedAudioFile) ?? outputURLs.first else {
            throw DownloadUseCaseError.outputNotFound
        }
        return audioURL
    }

    private static func isSupportedAudioFile(_ url: URL) -> Bool {
        ["wav", "aiff", "aif", "mp3", "m4a", "flac"].contains(url.pathExtension.lowercased())
    }
}

public struct YouTubeStemSeparationRequest: Equatable, Sendable {
    public var sourceURL: URL
    public var outputRootURL: URL
    public var preset: StemSeparationPreset

    public init(sourceURL: URL, outputRootURL: URL, preset: StemSeparationPreset) {
        self.sourceURL = sourceURL
        self.outputRootURL = outputRootURL
        self.preset = preset
    }
}

public struct YouTubeStemSeparationWorkflow: Sendable {
    private let downloader: any YouTubeAudioDownloading
    private let stemService: StemSeparationService
    private let jobRunner: any JobRunning

    public init(
        downloader: any YouTubeAudioDownloading,
        stemService: StemSeparationService,
        jobRunner: any JobRunning
    ) {
        self.downloader = downloader
        self.stemService = stemService
        self.jobRunner = jobRunner
    }

    @discardableResult
    public func startJob(request: YouTubeStemSeparationRequest) -> Job {
        jobRunner.enqueue(title: title(for: request.sourceURL), sourceToolID: StemSeparationService.toolID) { progress in
            try await run(request: request, progress: progress)
        }
    }

    private func run(
        request: YouTubeStemSeparationRequest,
        progress: JobProgress
    ) async throws {
        let downloadDirectory = request.outputRootURL
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("YouTube to Stems", isDirectory: true)
        try Task.checkCancellation()
        try stemService.validateOutputDirectory(downloadDirectory)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)

        progress.update(progress: 0, message: "Downloading audio…")
        let audioURL = try await downloader.downloadAudio(
            from: request.sourceURL,
            to: downloadDirectory,
            progress: mappedProgress(
                parent: progress,
                start: 0,
                span: 0.35,
                fallbackMessage: "Downloading audio…"
            )
        )
        progress.log("Downloaded audio: \(audioURL.path)")

        let stemRequest = StemSeparationRequest(
            inputURL: audioURL,
            outputRootURL: request.outputRootURL,
            preset: request.preset,
            title: audioURL.deletingPathExtension().lastPathComponent
        )
        progress.update(progress: 0.35, message: "Separating stems…")
        try await stemService.separate(
            request: stemRequest,
            progress: mappedProgress(
                parent: progress,
                start: 0.35,
                span: 0.65,
                fallbackMessage: "Separating stems…"
            )
        )
    }

    private func mappedProgress(
        parent: JobProgress,
        start: Double,
        span: Double,
        fallbackMessage: String
    ) -> JobProgress {
        JobProgress(
            updateHandler: { fraction, message in
                let normalized = fraction < 0 ? 0 : fraction
                parent.update(progress: start + (normalized * span), message: message ?? fallbackMessage)
            },
            logHandler: { message in
                parent.log(message)
            },
            outputHandler: { urls in
                parent.setOutputFileURLs(urls)
            }
        )
    }

    private func title(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return "YouTube to Stems: \(host)"
        }
        return "YouTube to Stems"
    }
}
