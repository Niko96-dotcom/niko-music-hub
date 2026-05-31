import AppCore
import Foundation

public enum SupportedAudioFileType: String, CaseIterable, Codable, Sendable {
    case m4a
    case mp3
    case wav
    case aiff
    case flac

    public init?(fileExtension: String) {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedExtension {
        case "m4a":
            self = .m4a
        case "mp3":
            self = .mp3
        case "wav", "wave":
            self = .wav
        case "aif", "aiff":
            self = .aiff
        case "flac":
            self = .flac
        default:
            return nil
        }
    }
}

public enum AudioConverterPath: String, Codable, Sendable {
    case native
    case ffmpeg
}

public struct ConversionRequest: Equatable, Sendable {
    public var sourceURL: URL
    public var outputDirectory: URL
    public var preset: AudioPreset
    public var sourceType: SupportedAudioFileType

    public init(
        sourceURL: URL,
        outputDirectory: URL,
        preset: AudioPreset,
        sourceType: SupportedAudioFileType
    ) {
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.preset = preset
        self.sourceType = sourceType
    }
}

public struct ConversionResult: Equatable, Sendable {
    public var sourceURL: URL
    public var outputURL: URL
    public var spec: WAVOutputSpec
    public var converterPath: AudioConverterPath

    public init(
        sourceURL: URL,
        outputURL: URL,
        spec: WAVOutputSpec,
        converterPath: AudioConverterPath
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.spec = spec
        self.converterPath = converterPath
    }
}

public enum AudioConversionError: LocalizedError, Equatable, Sendable {
    case unsupportedSourceType(URL)
    case sourceFileMissing(URL)
    case unreadableSource(URL)
    case outputDirectoryUnavailable(URL)
    case unsupportedBitDepth(Int)
    case missingFFmpeg(message: String)
    case outputSpecMismatch(expected: WAVOutputSpec, actual: WAVOutputSpec)
    case conversionFailed(String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSourceType(url):
            return "\(url.lastPathComponent) is not a supported audio file."
        case let .sourceFileMissing(url):
            return "Source file does not exist: \(url.path)"
        case let .unreadableSource(url):
            return "Source file could not be opened: \(url.path)"
        case let .outputDirectoryUnavailable(url):
            return "Output folder is unavailable: \(url.path)"
        case let .unsupportedBitDepth(bitDepth):
            return "\(bitDepth)-bit WAV output is not supported."
        case let .missingFFmpeg(message):
            return message
        case let .outputSpecMismatch(expected, actual):
            return "Expected \(expected.sampleRate)Hz \(expected.bitDepth)bit \(expected.channelCount)ch WAV, got \(actual.sampleRate)Hz \(actual.bitDepth)bit \(actual.channelCount)ch."
        case let .conversionFailed(reason):
            return "Audio conversion failed: \(reason)"
        case let .verificationFailed(reason):
            return "WAV verification failed: \(reason)"
        }
    }
}
