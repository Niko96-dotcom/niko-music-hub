#if DEBUG
import AppCore
import AVFAudio
import FeatureAudioRecorder
import Foundation

enum RecorderOutputInboxSmoke {
    @MainActor
    static func run() async throws -> [String: String] {
        let smokeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-recorder-smoke-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = smokeRoot.appendingPathComponent("Output", isDirectory: true)
        let inboxURL = smokeRoot.appendingPathComponent("output-inbox.json")
        defer { try? FileManager.default.removeItem(at: smokeRoot) }

        let capturePort = RecorderSmokeCapturePort()
        let inboxStore = JSONOutputInboxStore(storageURL: inboxURL)
        let viewModel = AudioRecorderViewModel(
            capturePort: capturePort,
            useCase: RecordSystemAudioUseCase(capturePort: capturePort),
            outputURL: outputDirectory,
            outputInboxStore: inboxStore
        )

        viewModel.filenameOverride = "E2E Recorder Smoke.wav"
        viewModel.maxDurationMinutes = 1

        await viewModel.startRecording()
        try await waitUntil { capturePort.recording }
        await viewModel.stopRecording()

        let recordedURL = try require(viewModel.lastRecordedURL, "recorder smoke did not produce a URL")
        let items = try inboxStore.listItems()
        guard items.count == 1 else {
            throw RecorderSmokeError("expected one Output Inbox item, got \(items.count)")
        }
        let item = items[0]
        let fileExists = FileManager.default.fileExists(atPath: recordedURL.path)
        let dragReady = OutputHandoff.isDragReady(item)
        guard fileExists else {
            throw RecorderSmokeError("recorded WAV missing at \(recordedURL.path)")
        }
        guard dragReady else {
            throw RecorderSmokeError("recorded WAV is not drag-ready")
        }
        guard item.sourceToolID.rawValue == "audio-recorder" else {
            throw RecorderSmokeError("unexpected source tool \(item.sourceToolID.rawValue)")
        }

        return [
            "recorder_output_drag_ready": "\(dragReady)",
            "recorder_output_file_exists": "\(fileExists)",
            "recorder_output_inbox_items": "\(items.count)",
            "recorder_output_source": item.sourceToolID.rawValue,
            "recorder_output_status": item.status.rawValue,
            "recorder_user_flow": "record_stop_inbox"
        ]
    }

    @MainActor
    private static func waitUntil(
        timeoutAttempts: Int = 100,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutAttempts {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RecorderSmokeError("timed out waiting for recorder smoke")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw RecorderSmokeError(message) }
        return value
    }
}

private final class RecorderSmokeCapturePort: AudioCapturePort, @unchecked Sendable {
    private var outputURL: URL?
    private var continuation: AsyncStream<RecorderAudioLevel>.Continuation?
    var recording = false

    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?
    ) async throws -> AsyncStream<RecorderAudioLevel> {
        self.outputURL = outputURL
        recording = true
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(RecorderAudioLevel(peak: 0.35, average: 0.18, elapsedTime: 0.1))
        }
    }

    func stopRecording() async throws -> RecorderResult {
        guard let outputURL else {
            throw RecorderError.apiError("Missing smoke output URL")
        }

        try writeValidWAV(to: outputURL)
        recording = false
        continuation?.finish()
        return RecorderResult(
            outputURL: outputURL,
            duration: 0.1,
            sampleRate: 44_100,
            bitDepth: 24,
            channelCount: 2,
            frameCount: 512,
            diagnostics: RecorderDiagnostics(
                outputDeviceUID: "e2e-smoke",
                tapSampleRate: 44_100,
                tapChannelCount: 2,
                inputFrameCount: 512,
                convertedFrameCount: 512,
                writtenFrameCount: 512
            )
        )
    }

    private func writeValidWAV(to outputURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
        let format = file.processingFormat
        let frameCount: AVAudioFrameCount = 512
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw RecorderError.writeError("Could not allocate smoke WAV buffer")
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    channelData[channel][frame] = Float(frame % 32) / 32.0
                }
            }
        }
        try file.write(from: buffer)
    }
}

private struct RecorderSmokeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
#endif
