import AppCore
import FeatureAudioConverter
import Foundation

public enum RecordingDisplayState: Equatable {
    case idle
    case permissionNeeded
    case incompatibleMacOS(version: String)
    case recording
    case stopping
    case error(RecorderError)
}

@MainActor
public final class AudioRecorderViewModel: ObservableObject {
    @Published public private(set) var recordingState: RecordingDisplayState = .idle
    @Published public var filenameOverride: String = ""
    @Published public var maxDurationMinutes: Int = 30
    @Published public private(set) var elapsedTime: TimeInterval = 0
    @Published public private(set) var currentLevel: RecorderAudioLevel?
    @Published public private(set) var error: RecorderError?
    @Published public private(set) var lastRecordedURL: URL?
    @Published public private(set) var showSaveConfirmation = false

    public var isRecording: Bool {
        recordingState == .recording
    }

    private var recordingTask: Task<Void, Never>?
    private let capturePort: AudioCapturePort
    private let useCase: RecordSystemAudioUseCase
    private let outputURL: URL
    private let outputInboxStore: any OutputInboxStore

    public init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        outputURL: URL,
        outputInboxStore: any OutputInboxStore
    ) {
        self.capturePort = capturePort
        self.useCase = useCase
        self.outputURL = outputURL
        self.outputInboxStore = outputInboxStore
    }

    public func startRecording() async {
        let permission = await capturePort.checkPermission()
        guard case .authorized = permission else {
            recordingState = .permissionNeeded
            return
        }

        guard capturePort.isCompatibleMacOS() else {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString = "\(version.majorVersion).\(version.minorVersion)"
            recordingState = .incompatibleMacOS(version: versionString)
            return
        }

        recordingState = .recording
        elapsedTime = 0
        currentLevel = nil
        error = nil
        showSaveConfirmation = false

        let maxDuration: TimeInterval? = maxDurationMinutes > 0
            ? TimeInterval(maxDurationMinutes * 60)
            : nil

        let config = RecordSystemAudioUseCase.Config(
            outputURL: outputURL,
            preset: .cubaseDefault,
            maxDuration: maxDuration,
            filenameOverride: filenameOverride.isEmpty ? nil : filenameOverride
        )
        let fileURL = useCase.resolvedOutputURL(config: config)

        recordingTask = Task {
            do {
                let stream = try await capturePort.startRecording(
                    outputURL: fileURL,
                    preset: config.preset,
                    maxDuration: config.maxDuration
                )

                for await level in stream {
                    if Task.isCancelled { break }
                    elapsedTime = level.elapsedTime
                    currentLevel = level
                }

                if Task.isCancelled {
                    let result = try await capturePort.stopRecording()
                    try await finalizeRecording(result)
                    return
                }

                let result = try await capturePort.stopRecording()
                try await finalizeRecording(result)
            } catch let recorderError as RecorderError {
                recordingState = .error(recorderError)
                error = recorderError
            } catch {
                let wrapped = RecorderError.verificationFailed(error.localizedDescription)
                recordingState = .error(wrapped)
                self.error = wrapped
            }
        }
    }

    public func stopRecording() async {
        guard recordingState == .recording else { return }
        recordingState = .stopping
        recordingTask?.cancel()
        await recordingTask?.value
        recordingTask = nil
    }

    public func requestPermission() async {
        let state = await capturePort.requestPermission()
        if case .authorized = state {
            recordingState = .idle
        }
    }

    private func finalizeRecording(_ result: RecorderResult) async throws {
        let verifier = WAVOutputVerifier()
        let expectedSpec = WAVOutputSpec(
            sampleRate: result.sampleRate,
            bitDepth: result.bitDepth,
            channelCount: result.channelCount
        )
        _ = try verifier.verify(url: result.outputURL, expectedSpec: expectedSpec)

        let item = OutputInboxItem(
            id: UUID(),
            fileURL: result.outputURL,
            sourceToolID: ToolFeatureID("audio-recorder"),
            createdAt: Date(),
            status: .available,
            metadata: [
                "duration": "\(result.duration)",
                "sampleRate": "\(result.sampleRate)",
                "bitDepth": "\(result.bitDepth)",
                "channels": "\(result.channelCount)"
            ]
        )
        try outputInboxStore.addItem(item)

        lastRecordedURL = result.outputURL
        showSaveConfirmation = true
        recordingState = .idle
        elapsedTime = 0
        currentLevel = nil
    }
}
