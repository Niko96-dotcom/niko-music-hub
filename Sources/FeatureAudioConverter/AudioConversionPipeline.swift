import AppCore
import Foundation

public typealias FFmpegConverterFactory = @Sendable (URL) -> any AudioConverting

public struct AudioConversionPipeline: AudioConverting, @unchecked Sendable {
    private let native: any AudioConverting
    private let ffmpegConverterFactory: FFmpegConverterFactory?
    private let healthChecker: FFmpegHealthChecker
    private let helperSettings: HelperToolSettings
    private let cachedFFmpegURL: LockedFFmpegURL

    public init(
        native: any AudioConverting = NativeAudioConverter(),
        helperSettings: HelperToolSettings,
        ffmpegConverterFactory: FFmpegConverterFactory? = {
            FFmpegAudioConverter(ffmpegURL: $0)
        },
        healthChecker: FFmpegHealthChecker = FFmpegHealthChecker()
    ) {
        self.native = native
        self.helperSettings = helperSettings
        self.ffmpegConverterFactory = ffmpegConverterFactory
        self.healthChecker = healthChecker
        self.cachedFFmpegURL = LockedFFmpegURL()
    }

    public func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        do {
            return try await native.convert(request)
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

        switch await healthChecker.availability(settings: helperSettings) {
        case .available:
            guard let ffmpegURL = healthChecker.resolvedFFmpegURL(settings: helperSettings) else {
                throw missingFFmpegError()
            }
            cachedFFmpegURL.value = ffmpegURL
            let ffmpeg = ffmpegConverterFactory(ffmpegURL)
            return try await ffmpeg.convert(request)
        case .missing:
            throw missingFFmpegError()
        case let .unusable(message):
            throw AudioConversionError.conversionFailed("FFmpeg is unavailable: \(message)")
        }
    }

    private func shouldAttemptFFmpegFallback(after error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return false
        }
        guard let conversionError = error as? AudioConversionError else {
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
        .missingFFmpeg(
            message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
        )
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
