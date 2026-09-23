import AppCore
import AVFAudio
import Foundation

public enum RecordingDisplayState: Equatable {
    case idle
    case permissionNeeded
    case incompatibleMacOS(version: String)
    case starting
    case recording
    case reconnecting
    case stopping
    case error(RecorderError)

    /// Only an explicit authorization failure belongs on the permission card.
    /// Missing PCM frames also occurs when no system audio is playing.
    static func presentation(for error: RecorderError) -> RecordingDisplayState {
        if indicatesCapturePermissionFailure(error) {
            return .permissionNeeded
        }
        return .error(error)
    }
}

private func indicatesCapturePermissionFailure(_ error: RecorderError) -> Bool {
    switch error {
    case .permissionDenied:
        return true
    case .apiError(let message):
        return messageIndicatesCapturePermissionFailure(message)
    default:
        return false
    }
}

private func messageIndicatesCapturePermissionFailure(_ message: String) -> Bool {
    let lowered = message.lowercased()
    let markers = [
        "not authorized",
        "unauthorized",
        "not permitted",
        "permission denied",
        "permission is denied",
        "user declined",
        "denied authorization",
    ]
    return markers.contains { lowered.contains($0) }
}

@MainActor
public final class AudioRecorderViewModel: ObservableObject {
    public static let toolID = ToolFeatureID("audio-recorder")
    /// How many finished recordings stay visible on the tool page (full history lives in the Output Inbox).
    static let recentRecordingsLimit = 5

    @Published public private(set) var recordingState: RecordingDisplayState = .idle {
        didSet {
            let active: Bool
            switch recordingState {
            case .starting, .recording, .reconnecting, .stopping: active = true
            default: active = false
            }
            AudioCaptureActivity.shared.setActive(active, owner: captureActivityID)
        }
    }
    private let captureActivityID = UUID()
    @Published public var filenameOverride: String = ""
    /// NMH-064: frozen preview of the next take's filename. Captured at
    /// appear / when idle so the idle field does not re-render a live
    /// `Date()` on every body evaluate.
    @Published public private(set) var proposedFilename: String = ""
    @Published public var maxDurationMinutes: Int = 30
    @Published public private(set) var elapsedTime: TimeInterval = 0
    @Published public private(set) var currentLevel: RecorderAudioLevel?
    @Published public private(set) var error: RecorderError?
    @Published public private(set) var lastRecordedURL: URL?
    @Published public private(set) var showSaveConfirmation = false
    @Published public private(set) var handoffWarningMessage: String?
    /// The last take was saved, but it is silent because macOS withheld system audio.
    @Published public private(set) var savedRecordingIsSilentFromBlockedCapture = false
    @Published public private(set) var recentRecordings: [OutputInboxItem] = []

    public var isRecording: Bool {
        recordingState == .recording
    }

    public var isCaptureActive: Bool {
        switch recordingState {
        case .starting, .recording, .reconnecting:
            true
        default:
            false
        }
    }

    private var recordingTask: Task<Void, Never>?
    private var inboxObservationTask: Task<Void, Never>?
    private let capturePort: AudioCapturePort
    private let useCase: RecordSystemAudioUseCase
    private let now: @Sendable () -> Date
    private let outputURLProvider: @MainActor () -> URL
    private let outputInboxStore: any OutputInboxStore
    private var isStartInFlight = false

    public convenience init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        outputURL: URL,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            capturePort: capturePort,
            useCase: useCase,
            outputURLProvider: { outputURL },
            outputInboxStore: outputInboxStore,
            initialMaxDurationMinutes: initialMaxDurationMinutes,
            now: now
        )
    }

    public init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        outputURLProvider: @escaping @MainActor () -> URL,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.capturePort = capturePort
        self.useCase = useCase
        self.now = now
        self.outputURLProvider = outputURLProvider
        self.outputInboxStore = outputInboxStore
        self.maxDurationMinutes = RecordingDurationOptions.normalized(initialMaxDurationMinutes)
        refreshProposedFilename()
    }

    deinit {
        inboxObservationTask?.cancel()
        let owner = captureActivityID
        Task { @MainActor in AudioCaptureActivity.shared.setActive(false, owner: owner) }
    }

    public func startRecording() async {
        guard !isStartInFlight,
              !isCaptureActive,
              recordingState != .stopping
        else {
            return
        }

        isStartInFlight = true
        defer { isStartInFlight = false }
        savedRecordingIsSilentFromBlockedCapture = false

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

        recordingState = .starting
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
            presentFailure(recorderError)
            return
        } catch {
            presentFailure(RecorderError.writeError(error.localizedDescription))
            return
        }

        recordingTask = Task {
            do {
                let stream = try await capturePort.startRecording(
                    outputURL: fileURL,
                    preset: config.preset,
                    maxDuration: config.maxDuration
                )

                guard !Task.isCancelled else { return }
                recordingState = .recording
                HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.recordingStarted)

                for await level in stream {
                    if Task.isCancelled { break }
                    elapsedTime = level.elapsedTime
                    currentLevel = level
                }

                if !Task.isCancelled,
                   recordingState == .recording || recordingState == .reconnecting {
                    Task { @MainActor [weak self] in
                        await self?.stopRecording()
                    }
                }
            } catch is CancellationError {
                currentLevel = nil
                if recordingState != .stopping {
                    recordingState = .idle
                }
            } catch let recorderError as RecorderError {
                presentFailure(recorderError)
            } catch {
                presentFailure(RecorderError.verificationFailed(error.localizedDescription))
            }
        }
    }

    public func stopRecording() async {
        await stopRecording(awaitingCurrentTask: true)
    }

    private func stopRecording(awaitingCurrentTask: Bool) async {
        guard isCaptureActive else { return }
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
        } catch is CancellationError {
            taskToAwait?.cancel()
            recordingTask = nil
            currentLevel = nil
            recordingState = .idle
            error = nil
        } catch let recorderError as RecorderError {
            taskToAwait?.cancel()
            recordingTask = nil
            presentFailure(recorderError)
        } catch {
            taskToAwait?.cancel()
            recordingTask = nil
            presentFailure(RecorderError.verificationFailed(error.localizedDescription))
        }
    }

    public func requestPermission() async {
        let state = await capturePort.requestPermission()
        if case .authorized = state {
            await startRecording()
            return
        }
        recordingState = .permissionNeeded
    }

    private func presentFailure(_ recorderError: RecorderError) {
        currentLevel = nil
        recordingState = .presentation(for: recorderError)
        error = recorderError
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
                // Callbacks without PCM do not establish a permission denial.
                // Keep the no-audio failure distinct from a corrupt output file.
                if let diagnostics = result.diagnostics,
                   diagnostics.inputBufferCallbackCount > 0,
                   diagnostics.inputFrameCount == 0 {
                    throw RecorderError.noAudioCaptured(
                        "macOS did not deliver any audio frames to the recorder. "
                            + "Start audio playback and try again. If it keeps happening, allow Niko Music Hub in System Settings → Privacy & Security → Screen & System Audio Recording. CoreAudio diagnostics: \(diagnostics.summary)."
                    )
                }
                // Frames arrived but nothing was written (a genuine converter/write/WAV-spec
                // failure) — keep this as a verification failure.
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
            sourceToolID: Self.toolID,
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
        refreshProposedFilename()
        HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.recordingStopped)
        loadRecentRecordings()
        if result.silentBecauseCaptureWasBlocked {
            // The take is kept (and handed off) like any other; the card explains why
            // it is silent.
            savedRecordingIsSilentFromBlockedCapture = true
            error = .permissionDenied
            recordingState = .permissionNeeded
        }
    }

    public func dismissSaveConfirmation() {
        showSaveConfirmation = false
        handoffWarningMessage = nil
    }

    /// NMH-043: every error card action must do something. Dismiss clears the
    /// visible error/incompatible card and returns the tool to idle.
    public func dismissError() {
        error = nil
        savedRecordingIsSilentFromBlockedCapture = false
        recordingState = .idle
    }

    /// NMH-064: snapshot the next take's default filename with a frozen
    /// instant so the idle field matches the writer's format without
    /// re-rendering a live `Date()` on every view evaluate.
    public func refreshProposedFilename() {
        let frozen = now()
        proposedFilename = useCase.generateOutputFilename(override: nil, now: { frozen })
    }

    public func onAppear() {
        refreshProposedFilename()
        loadRecentRecordings()
        guard inboxObservationTask == nil else { return }
        inboxObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .outputInboxDidChange) {
                self?.loadRecentRecordings()
            }
        }
    }

    public func loadRecentRecordings() {
        let items = (try? outputInboxStore.listItems()) ?? []
        recentRecordings = Array(
            items
                .filter { $0.sourceToolID == Self.toolID }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(Self.recentRecordingsLimit)
        )
    }

    private static func handoffWarningMessage(for error: Error) -> String {
        "Recording saved, but Output Inbox could not save the handoff. \(error.localizedDescription)"
    }
}
