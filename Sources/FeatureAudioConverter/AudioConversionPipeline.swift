import AppCore
import Foundation

public typealias FFmpegConverterFactory = @Sendable (URL) -> any AudioConverting

public struct AudioConversionPipeline: AudioConverting, @unchecked Sendable {
    private let native: any AudioConverting
    private let ffmpegConverterFactory: FFmpegConverterFactory?
    private let helperProbe: HelperToolProbe
    private let helperSettings: HelperToolSettings
    private let cachedFFmpegURL: LockedFFmpegURL

    public init(
        native: any AudioConverting = NativeAudioConverter(),
        helperSettings: HelperToolSettings,
        ffmpegConverterFactory: FFmpegConverterFactory?,
        helperProbe: HelperToolProbe
    ) {
        self.native = native
        self.helperSettings = helperSettings
        self.ffmpegConverterFactory = ffmpegConverterFactory
        self.helperProbe = helperProbe
        self.cachedFFmpegURL = LockedFFmpegURL()
    }

    public func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        do {
            return try await native.convert(request)
        } catch let outputError as NativeOutputWriteError {
            // Disk full, read-only or permission errors fail the same with FFmpeg;
            // keep the native error so the real cause reaches the row.
            throw outputError.underlying
        } catch {
            guard shouldAttemptFFmpegFallback(after: error) else {
                throw error
            }
            return try await convertWithFFmpeg(request)
        }
    }

    private func convertWithFFmpeg(_ request: ConversionRequest) async throws -> ConversionResult {
        guard let ffmpegConverterFactory else {
            throw missingFFmpegError()
        }

        if let cachedURL = cachedFFmpegURL.value {
            let ffmpeg = ffmpegConverterFactory(cachedURL)
            return try await ffmpeg.convert(request)
        }

        switch await helperProbe.status(of: .ffmpeg, settings: helperSettings) {
        case .ready, .outdated:
            guard let ffmpegURL = helperProbe.locator.resolve(.ffmpeg, settings: helperSettings) else {
                throw missingFFmpegError()
            }
            cachedFFmpegURL.value = ffmpegURL
            let ffmpeg = ffmpegConverterFactory(ffmpegURL)
            return try await ffmpeg.convert(request)
        case .missing:
            throw missingFFmpegError()
        case let .broken(message):
            // Helper-unavailable category keeps the Choose FFmpeg recovery; the row shows fixed copy.
            throw AudioConversionError.missingFFmpeg(message: "FFmpeg is unavailable: \(message)")
        }
    }

    private func shouldAttemptFFmpegFallback(after error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return false
        }
        guard let conversionError = error as? AudioConversionError else {
            // Output-side failures arrive as NativeOutputWriteError and never get here;
            // anything else is a source AVFoundation could not read, which FFmpeg may.
            return true
        }

        switch conversionError {
        case .unsupportedSourceType,
             .unreadableSource,
             .outputSpecMismatch,
             .conversionFailed,
             .verificationFailed:
            return true
        case .sourceFileMissing,
             .outputDirectoryUnavailable,
             .unsupportedBitDepth,
             .missingFFmpeg:
            return false
        }
    }

    private func missingFFmpegError() -> AudioConversionError {
        .missingFFmpeg(message: AudioConverterCopy.missingFFmpeg)
    }
}

private final class LockedFFmpegURL: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URL?

    var value: URL? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
