import AVFoundation
import AppCore
import Foundation

public protocol AudioConverting: Sendable {
    func convert(_ request: ConversionRequest) async throws -> ConversionResult
}

public struct NativeAudioConverter: AudioConverting, @unchecked Sendable {
    private let outputFileNamer: OutputFileNamer
    private let verifier: WAVOutputVerifier
    private let fileManager: FileManager

    public init(
        outputFileNamer: OutputFileNamer = OutputFileNamer(),
        verifier: WAVOutputVerifier = WAVOutputVerifier(),
        fileManager: FileManager = .default
    ) {
        self.outputFileNamer = outputFileNamer
        self.verifier = verifier
        self.fileManager = fileManager
    }

    public func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        guard fileManager.fileExists(atPath: request.sourceURL.path) else {
            throw AudioConversionError.sourceFileMissing(request.sourceURL)
        }

        try fileManager.createDirectory(
            at: request.outputDirectory,
            withIntermediateDirectories: true
        )

        let sourceFile = try AVAudioFile(forReading: request.sourceURL)
        let channelCount = resolvedChannelCount(
            for: sourceFile.fileFormat.channelCount,
            mode: request.preset.channelMode
        )
        let expectedSpec = WAVOutputSpec(
            preset: request.preset,
            channelCount: Int(channelCount)
        )
        let finalOutputURL = outputFileNamer.plannedOutputURL(
            for: request.outputDirectory,
            sourceURL: request.sourceURL,
            preset: request.preset,
            existingFileExists: { [fileManager] in
                fileManager.fileExists(atPath: $0.path)
            }
        )
        let temporaryOutputURL = makeTemporaryOutputURL(for: finalOutputURL)

        do {
            try removeFileIfNeeded(at: temporaryOutputURL)
            try writeConvertedWAV(
                sourceFile: sourceFile,
                outputURL: temporaryOutputURL,
                expectedSpec: expectedSpec
            )

            let verifiedSpec = try verifier.verify(
                url: temporaryOutputURL,
                expectedSpec: expectedSpec
            )

            guard !fileManager.fileExists(atPath: finalOutputURL.path) else {
                throw AudioConversionError.conversionFailed(
                    "Output file already exists: \(finalOutputURL.lastPathComponent)"
                )
            }

            try fileManager.moveItem(at: temporaryOutputURL, to: finalOutputURL)
            return ConversionResult(
                sourceURL: request.sourceURL,
                outputURL: finalOutputURL,
                spec: verifiedSpec,
                converterPath: .native
            )
        } catch {
            try? removeFileIfNeeded(at: temporaryOutputURL)
            throw error
        }
    }

    private func writeConvertedWAV(
        sourceFile: AVAudioFile,
        outputURL: URL,
        expectedSpec: WAVOutputSpec
    ) throws {
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(expectedSpec.sampleRate),
            channels: AVAudioChannelCount(expectedSpec.channelCount),
            interleaved: false
        ) else {
            throw AudioConversionError.conversionFailed("Could not build output audio format.")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: expectedSpec.bitDepth,
            AVSampleRateKey: Double(expectedSpec.sampleRate),
            AVNumberOfChannelsKey: expectedSpec.channelCount,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to: processingFormat
        ) else {
            throw AudioConversionError.conversionFailed("Could not create AVAudioConverter.")
        }

        try streamConvertedAudio(
            sourceFile: sourceFile,
            outputFile: outputFile,
            outputFormat: processingFormat,
            converter: converter
        )
    }

    private func streamConvertedAudio(
        sourceFile: AVAudioFile,
        outputFile: AVAudioFile,
        outputFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) throws {
        let inputFrameCapacity: AVAudioFrameCount = 4_096
        let inputState = ConverterInputState()

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: inputFrameCapacity
            ) else {
                throw AudioConversionError.conversionFailed("Could not allocate output buffer.")
            }

            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, outStatus in
                guard !inputState.sourceDidFinish else {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                let remainingFrames = sourceFile.length - sourceFile.framePosition
                guard remainingFrames > 0 else {
                    inputState.sourceDidFinish = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                let framesToRead = AVAudioFrameCount(
                    min(Int64(inputFrameCapacity), remainingFrames)
                )
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat,
                    frameCapacity: framesToRead
                ) else {
                    inputState.error = AudioConversionError.conversionFailed(
                        "Could not allocate input buffer."
                    )
                    inputState.sourceDidFinish = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    try sourceFile.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    inputState.error = error
                    inputState.sourceDidFinish = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                guard inputBuffer.frameLength > 0 else {
                    inputState.sourceDidFinish = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let inputError = inputState.error {
                throw inputError
            }
            if let conversionError {
                throw conversionError
            }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry:
                if inputState.sourceDidFinish && outputBuffer.frameLength == 0 {
                    return
                }
                continue
            case .endOfStream:
                return
            case .error:
                throw AudioConversionError.conversionFailed("AVAudioConverter failed.")
            @unknown default:
                throw AudioConversionError.conversionFailed("Unknown AVAudioConverter status.")
            }
        }
    }

    private func resolvedChannelCount(
        for sourceChannelCount: AVAudioChannelCount,
        mode: AudioChannelMode
    ) -> AVAudioChannelCount {
        switch mode {
        case .preserveMonoStereo:
            return sourceChannelCount <= 1 ? 1 : 2
        case .mono:
            return 1
        case .stereo:
            return 2
        }
    }

    private func makeTemporaryOutputURL(for finalOutputURL: URL) -> URL {
        let baseName = finalOutputURL.deletingPathExtension().lastPathComponent
        let temporaryName = "\(baseName).\(UUID().uuidString).tmp.wav"
        return finalOutputURL
            .deletingLastPathComponent()
            .appendingPathComponent(temporaryName)
    }

    private func removeFileIfNeeded(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var sourceDidFinish = false
    var error: Error?
}
