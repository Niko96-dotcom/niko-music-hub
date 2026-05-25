import AppCore
import AVFAudio
import Foundation

public final class WAVRecorderWriter: @unchecked Sendable {
    private let outputURL: URL
    private let preset: AudioPreset
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var _isRecording = false

    public init(outputURL: URL, preset: AudioPreset) throws {
        self.outputURL = outputURL
        self.preset = preset

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: preset.sampleRate,
            AVNumberOfChannelsKey: preset.channelCount,
            AVLinearPCMBitDepthKey: preset.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        self.audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        self._isRecording = true
        self.startTime = Date()
    }

    public func writeBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard _isRecording, let audioFile = audioFile else {
            return
        }
        try audioFile.write(from: buffer)
    }

    public func finalize() throws -> RecorderResult {
        guard _isRecording else {
            throw RecorderError.writeError("Recorder is not active")
        }

        _isRecording = false

        if let start = startTime {
            accumulatedDuration = Date().timeIntervalSince(start)
        }

        audioFile = nil

        return RecorderResult(
            outputURL: outputURL,
            duration: accumulatedDuration,
            sampleRate: preset.sampleRate,
            bitDepth: preset.bitDepth,
            channelCount: preset.channelCount
        )
    }

    public var currentTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    public var isRecording: Bool {
        _isRecording
    }
}
