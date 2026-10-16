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
            // Helper-unavailable category keeps the Choose FFmpeg recovery; the row shows fixed copy.
            throw AudioConversionError.missingFFmpeg(message: "FFmpeg is unavailable: \(message)")
        }
    }

    private func shouldAttemptFFmpegFallback(after error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return false
        }
        guard let conversionError = error as? AudioConversionError else {
            // Output-side I/O (disk full, read-only, permission) fails the same with FFmpeg;
            // keep the native error so the real cause reaches the row.
            return !isOutputIOFailure(error as NSError)
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

    private func isOutputIOFailure(_ error: NSError) -> Bool {
        let outputPOSIXCodes: Set<Int> = [
            Int(ENOSPC), Int(EDQUOT), Int(EROFS), Int(EACCES), Int(EPERM), Int(EIO)
        ]
        switch error.domain {
        case NSCocoaErrorDomain:
            if (NSFileWriteUnknownError...NSFileWriteVolumeReadOnlyError).contains(error.code) {
                return true
            }
        case NSPOSIXErrorDomain:
            if outputPOSIXCodes.contains(error.code) {
                return true
            }
        case NSOSStatusErrorDomain:
            // Core Audio passes errno values through as OSStatus.
            if outputPOSIXCodes.contains(error.code) {
                return true
            }
        default:
            break
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOutputIOFailure(underlying)
        }
        return false
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
