import AVFoundation
import Foundation

public enum WAVOutputVerificationError: LocalizedError, Equatable, Sendable {
    case missingFile(URL)
    case unreadableFile(URL)
    case nonWAVOrPCM(URL)
    case sampleRateMismatch(expected: Int, actual: Int)
    case bitDepthMismatch(expected: Int, actual: Int)
    case channelCountMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            return "WAV output is missing: \(url.path)"
        case let .unreadableFile(url):
            return "WAV output could not be opened: \(url.path)"
        case let .nonWAVOrPCM(url):
            return "Output is not a WAV PCM file: \(url.path)"
        case let .sampleRateMismatch(expected, actual):
            return "Expected WAV sample rate \(expected)Hz, got \(actual)Hz."
        case let .bitDepthMismatch(expected, actual):
            return "Expected WAV bit depth \(expected), got \(actual)."
        case let .channelCountMismatch(expected, actual):
            return "Expected WAV channel count \(expected), got \(actual)."
        }
    }
}

public struct WAVOutputVerifier: Sendable {
    private let fileExists: @Sendable (String) -> Bool

    public init(
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.fileExists = fileExists
    }

    public func verify(
        url: URL,
        expectedSpec: WAVOutputSpec
    ) throws -> WAVOutputSpec {
        guard fileExists(url.path) else {
            throw WAVOutputVerificationError.missingFile(url)
        }

        guard isWAVFile(url) else {
            throw WAVOutputVerificationError.nonWAVOrPCM(url)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WAVOutputVerificationError.unreadableFile(url)
        }

        guard isLinearPCM(file.fileFormat) else {
            throw WAVOutputVerificationError.nonWAVOrPCM(url)
        }

        let actualSpec = WAVOutputSpec(
            sampleRate: Int(file.fileFormat.sampleRate.rounded()),
            bitDepth: Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel),
            channelCount: Int(file.fileFormat.channelCount)
        )

        try verifySampleRate(actualSpec.sampleRate, expected: expectedSpec.sampleRate)
        try verifyBitDepth(actualSpec.bitDepth, expected: expectedSpec.bitDepth)
        try verifyChannelCount(actualSpec.channelCount, expected: expectedSpec.channelCount)

        return actualSpec
    }

    private func isWAVFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "wav" || fileExtension == "wave"
    }

    private func isLinearPCM(_ format: AVAudioFormat) -> Bool {
        format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM
    }

    private func verifySampleRate(_ actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw WAVOutputVerificationError.sampleRateMismatch(
                expected: expected,
                actual: actual
            )
        }
    }

    private func verifyBitDepth(_ actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw WAVOutputVerificationError.bitDepthMismatch(
                expected: expected,
                actual: actual
            )
        }
    }

    private func verifyChannelCount(_ actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw WAVOutputVerificationError.channelCountMismatch(
                expected: expected,
                actual: actual
            )
        }
    }
}
