import Foundation

enum YtDlpDownloadCommandBuilder {
    static let progressTemplate = "NIKO_PROGRESS:%(progress)s"
    static let filePrintMarker = "after_move:NIKO_MUSIC_HUB_FILE:%(filepath)s"

    static func downloadArguments(for request: DownloadRequest) -> [String] {
        let outputPath = request.outputDirectory.appendingPathComponent(request.outputTemplate).path
        let formatArgs = YtDlpFormatArgumentBuilder.arguments(for: request.formatSelection)

        var args: [String] = [
            "--newline",
            "--no-overwrites",
            "--no-playlist",
            "--socket-timeout", "30",
            "--retries", "1",
            "--fragment-retries", "1",
            "--extractor-retries", "1",
            "--progress",
            "-f", formatArgs.formatSelector,
        ]
        args.append(contentsOf: formatArgs.extraArguments)
        if let ffmpegLocationURL = request.ffmpegLocationURL {
            args.append(contentsOf: ["--ffmpeg-location", ffmpegLocationURL.path])
        }
        args.append(contentsOf: [
            "--progress-template", progressTemplate,
            "--print", filePrintMarker,
            "-o", outputPath,
            request.sourceURL.absoluteString,
        ])
        return args
    }

    static func simulateArguments(
        formatSelection: DownloadFormatSelection,
        sourceURL: URL,
        ffmpegLocationURL: URL?
    ) -> [String] {
        let formatArgs = YtDlpFormatArgumentBuilder.arguments(for: formatSelection)
        var args: [String] = [
            "--simulate",
            "--no-playlist",
            "-f", formatArgs.formatSelector,
        ]
        args.append(contentsOf: formatArgs.extraArguments)
        if let ffmpegLocationURL {
            args.append(contentsOf: ["--ffmpeg-location", ffmpegLocationURL.path])
        }
        args.append(contentsOf: ["--print", "%(title)s", sourceURL.absoluteString])
        return args
    }
}
