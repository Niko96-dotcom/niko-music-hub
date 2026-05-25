import AVFoundation
import AppCore
import Foundation

public struct FFmpegAudioConverter: AudioConverting, @unchecked Sendable {
    private static let cubaseReadySampleRate = 44100

    private let ffmpegURL: URL
    private let runner: any ExternalProcessRunning
    private let outputFileNamer: OutputFileNamer
    private let verifier: WAVOutputVerifier
    private let fileManager: FileManager

    public init(
        ffmpegURL: URL,
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        outputFileNamer: OutputFileNamer = OutputFileNamer(),
        verifier: WAVOutputVerifier = WAVOutputVerifier(),
        fileManager: FileManager = .default
    ) {
        self.ffmpegURL = ffmpegURL
        self.runner = runner
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

        let channelCount = try await resolvedChannelCount(for: request)
        let expectedSpec = WAVOutputSpec(
            preset: request.preset,
            channelCount: channelCount
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
            let result = try await runner.run(
                ExternalProcessRequest(
                    executableURL: ffmpegURL,
                    arguments: arguments(
                        sourceURL: request.sourceURL,
                        outputURL: temporaryOutputURL,
                        expectedSpec: expectedSpec
                    )
                )
            )

            guard result.exitCode == 0 else {
                throw AudioConversionError.conversionFailed(diagnosticMessage(from: result))
            }

            let verifiedSpec: WAVOutputSpec
            do {
                verifiedSpec = try verifier.verify(
                    url: temporaryOutputURL,
                    expectedSpec: expectedSpec
                )
            } catch {
                throw AudioConversionError.verificationFailed(error.localizedDescription)
            }

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
                converterPath: .ffmpeg
            )
        } catch {
            try? removeFileIfNeeded(at: temporaryOutputURL)
            throw error
        }
    }

    private func arguments(
        sourceURL: URL,
        outputURL: URL,
        expectedSpec: WAVOutputSpec
    ) throws -> [String] {
        [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i",
            sourceURL.path,
            "-vn",
            "-ar",
            sampleRateArgument(for: expectedSpec.sampleRate),
            "-ac",
            "\(expectedSpec.channelCount)",
            "-c:a",
            try codecName(for: expectedSpec.bitDepth),
            outputURL.path
        ]
    }

    private func sampleRateArgument(for sampleRate: Int) -> String {
        if sampleRate == Self.cubaseReadySampleRate {
            return "44100"
        }
        return "\(sampleRate)"
    }

    private func codecName(for bitDepth: Int) throws -> String {
        switch bitDepth {
        case 16:
            return "pcm_s16le"
        case 24:
            return "pcm_s24le"
        default:
            throw AudioConversionError.unsupportedBitDepth(bitDepth)
        }
    }

    private func resolvedChannelCount(for request: ConversionRequest) async throws -> Int {
        switch request.preset.channelMode {
        case .preserveMonoStereo:
            if let channelCount = sourceChannelCount(for: request.sourceURL) {
                return channelCount <= 1 ? 1 : 2
            }
            if let channelCount = try await probeChannelCountWithFFmpeg(for: request.sourceURL) {
                return channelCount <= 1 ? 1 : 2
            }
            throw AudioConversionError.conversionFailed(
                "Could not determine source channel count for preserve mono/stereo."
            )
        case .mono:
            return 1
        case .stereo:
            return 2
        }
    }

    private func sourceChannelCount(for sourceURL: URL) -> Int? {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            return nil
        }
        return Int(sourceFile.fileFormat.channelCount)
    }

    private func probeChannelCountWithFFmpeg(for sourceURL: URL) async throws -> Int? {
        let result = try await runner.run(
            ExternalProcessRequest(
                executableURL: ffmpegURL,
                arguments: ["-hide_banner", "-nostdin", "-i", sourceURL.path]
            )
        )
        return parsedChannelCount(from: "\(result.standardOutput)\n\(result.standardError)")
    }

    private func parsedChannelCount(from diagnostics: String) -> Int? {
        for line in diagnostics.split(whereSeparator: \.isNewline).map(String.init) {
            let lowercasedLine = line.lowercased()
            guard lowercasedLine.contains("audio:") else { continue }
            if lowercasedLine.contains("mono") {
                return 1
            }
            if lowercasedLine.contains("stereo")
                || lowercasedLine.contains("2.1")
                || lowercasedLine.contains("3.0")
                || lowercasedLine.contains("4.0")
                || lowercasedLine.contains("5.1")
                || lowercasedLine.contains("7.1") {
                return 2
            }
            if let channelCount = channelCount(from: lowercasedLine) {
                return channelCount
            }
        }
        return nil
    }

    private func channelCount(from line: String) -> Int? {
        guard let range = line.range(
            of: #"[0-9]+ channels"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let text = line[range].split(separator: " ").first.map(String.init) ?? ""
        return Int(text)
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

    private func diagnosticMessage(from result: ExternalProcessResult) -> String {
        let details = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "FFmpeg exited with code \(result.exitCode)."
        }
        return "FFmpeg exited with code \(result.exitCode): \(trimmed)"
    }
}
