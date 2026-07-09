import AppCore
import AVFAudio
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
    @Published public private(set) var handoffWarningMessage: String?

    public var isRecording: Bool {
        recordingState == .recording
    }

    private var recordingTask: Task<Void, Never>?
    private let capturePort: AudioCapturePort
    private let useCase: RecordSystemAudioUseCase
    private let outputURLProvider: @MainActor () -> URL
    private let outputInboxStore: any OutputInboxStore
    private var isStartInFlight = false

    public convenience init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        outputURL: URL,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30
    ) {
        self.init(
            capturePort: capturePort,
            useCase: useCase,
            outputURLProvider: { outputURL },
            outputInboxStore: outputInboxStore,
            initialMaxDurationMinutes: initialMaxDurationMinutes
        )
    }

    public init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        outputURLProvider: @escaping @MainActor () -> URL,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30
    ) {
        self.capturePort = capturePort
        self.useCase = useCase
        self.outputURLProvider = outputURLProvider
        self.outputInboxStore = outputInboxStore
        self.maxDurationMinutes = RecordingDurationOptions.normalized(initialMaxDurationMinutes)
    }

    public func startRecording() async {
        guard !isStartInFlight,
              recordingState != .recording,
              recordingState != .stopping
        else {
            return
        }

        isStartInFlight = true
        defer { isStartInFlight = false }

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
        handoffWarningMessage = nil
        showSaveConfirmation = false

        let maxDuration: TimeInterval? = maxDurationMinutes > 0
            ? TimeInterval(maxDurationMinutes * 60)
            : nil

        let config = RecordSystemAudioUseCase.Config(
            outputURL: outputURLProvider(),
            preset: .cubaseDefault,
            maxDuration: maxDuration,
            filenameOverride: filenameOverride.isEmpty ? nil : filenameOverride
        )
        let fileURL: URL
        do {
            fileURL = try useCase.prepareOutputURL(config: config)
        } catch let recorderError as RecorderError {
            recordingState = .error(recorderError)
            error = recorderError
            return
        } catch {
            let wrapped = RecorderError.writeError(error.localizedDescription)
            recordingState = .error(wrapped)
            self.error = wrapped
            return
        }

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

                if !Task.isCancelled, recordingState == .recording {
                    Task { @MainActor [weak self] in
                        await self?.stopRecording()
                    }
                }
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
        await stopRecording(awaitingCurrentTask: true)
    }

    private func stopRecording(awaitingCurrentTask: Bool) async {
        guard recordingState == .recording else { return }
        recordingState = .stopping
        let taskToAwait = recordingTask

        do {
            let result = try await capturePort.stopRecording()
            taskToAwait?.cancel()
            if awaitingCurrentTask {
                await taskToAwait?.value
            }
            recordingTask = nil
            try await finalizeRecording(result)
        } catch let recorderError as RecorderError {
            taskToAwait?.cancel()
            recordingTask = nil
            currentLevel = nil
            recordingState = .error(recorderError)
            error = recorderError
        } catch {
            taskToAwait?.cancel()
            recordingTask = nil
            currentLevel = nil
            let wrapped = RecorderError.verificationFailed(error.localizedDescription)
            recordingState = .error(wrapped)
            self.error = wrapped
        }
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

        do {
            if let diagnostics = result.diagnostics, diagnostics.writeErrorCount > 0 {
                throw RecorderError.writeError(
                    "Recording write failed (\(diagnostics.writeErrorCount) errors). CoreAudio diagnostics: \(diagnostics.summary)."
                )
            }
            _ = try verifier.verify(url: result.outputURL, expectedSpec: expectedSpec)
            let file = try AVAudioFile(forReading: result.outputURL)
            guard file.length > 0 else {
                var message = "Recording contained no audio frames."
                if let diagnostics = result.diagnostics {
                    message += " CoreAudio diagnostics: \(diagnostics.summary)."
                }
                throw RecorderError.verificationFailed(message)
            }
        } catch {
            try? FileManager.default.removeItem(at: result.outputURL)
            throw error
        }

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
        do {
            try outputInboxStore.addItem(item)
            handoffWarningMessage = nil
        } catch {
            handoffWarningMessage = Self.handoffWarningMessage(for: error)
        }

        lastRecordedURL = result.outputURL
        showSaveConfirmation = true
        recordingState = .idle
        elapsedTime = 0
        currentLevel = nil
    }

    public func dismissSaveConfirmation() {
        showSaveConfirmation = false
        handoffWarningMessage = nil
    }

    private static func handoffWarningMessage(for error: Error) -> String {
        "Recording saved, but Output Inbox could not save the handoff. \(error.localizedDescription)"
    }
}
