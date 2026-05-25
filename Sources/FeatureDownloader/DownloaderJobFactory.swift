import AppCore
import Foundation

public struct DownloaderJobFactory: Sendable {
    public init() {}

    public func makeJobOptions(
        sourceURL: URL,
        outputDirectory: URL,
        fileNameTemplate: String = "%(title)s.%(ext)s",
        retries: Int = 3
    ) -> DownloadJobOptions {
        DownloadJobOptions(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            fileNameTemplate: fileNameTemplate,
            retries: retries
        )
    }
}