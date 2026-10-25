import AVFAudio
import AppCore
import Foundation
import NikoMusicCore

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
    @Published public private(set) var recordingState: RecordingDisplayState = .idle {
        didSet {
            let active = Self.isActive(recordingState)
            audioCaptureActivity?.setActive(active, owner: captureActivityID)
            if active != Self.isActive(oldValue) {
                registerTakeForQuit(active)
            }
        }
    }
    /// The app's recording signal (`ToolContext.audioCaptureActivity`): held from start until
    /// the take is finalized; archive preview pauses on it. Nil when nobody listens (tests).
    private let audioCaptureActivity: AudioCaptureActivity?
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
    /// The failed take's file when audio recorded before the error is still on disk.
    @Published public private(set) var keptPartialTakeURL: URL?
    @Published private var stoppingBeforeCapture = false
    /// The five newest takes, for the list on this page. The full history lives in the Output Inbox.
    public let recentOutputs: ToolRecentOutputs

    public var captureStartupMessage: String? {
        if recordingState == .starting {
            return "If macOS asks for system-audio permission, answer the prompt. Recording begins when audio is ready."
        }
        if recordingState == .stopping, stoppingBeforeCapture {
            return "Answer any macOS system-audio permission prompt to finish stopping. Audio startup has not finished."
        }
        return nil
    }

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
    private let capturePort: AudioCapturePort
    private let useCase: RecordSystemAudioUseCase
    private let now: @Sendable () -> Date
    private let destinationProvider: @MainActor () throws -> ToolOutputDestination
    private let outputInboxStore: any OutputInboxStore
    private let jobStatusCenter: ShellJobStatusCenter?
    private var isStartInFlight = false
    private var activeTakeURL: URL?

    public convenience init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        destination: ToolOutputDestination,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30,
        jobStatusCenter: ShellJobStatusCenter? = nil,
        audioCaptureActivity: AudioCaptureActivity? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            capturePort: capturePort,
            useCase: useCase,
            destinationProvider: { destination },
            outputInboxStore: outputInboxStore,
            initialMaxDurationMinutes: initialMaxDurationMinutes,
            jobStatusCenter: jobStatusCenter,
            audioCaptureActivity: audioCaptureActivity,
            now: now
        )
    }

    public init(
        capturePort: AudioCapturePort,
        useCase: RecordSystemAudioUseCase,
        destinationProvider: @escaping @MainActor () throws -> ToolOutputDestination,
        outputInboxStore: any OutputInboxStore,
        initialMaxDurationMinutes: Int = 30,
        jobStatusCenter: ShellJobStatusCenter? = nil,
        audioCaptureActivity: AudioCaptureActivity? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.capturePort = capturePort
        self.useCase = useCase
        self.now = now
        self.destinationProvider = destinationProvider
        self.outputInboxStore = outputInboxStore
        self.recentOutputs = ToolRecentOutputs(store: outputInboxStore, toolID: .audioRecorder, limit: 5)
        self.jobStatusCenter = jobStatusCenter
        self.audioCaptureActivity = audioCaptureActivity
        self.maxDurationMinutes = RecordingDurationOptions.normalized(initialMaxDurationMinutes)
        refreshProposedFilename()
    }

    deinit {
        jobStatusCenter?.setExtraJob(sourceID: ShellJobExtraSourceID.audioRecorder, status: nil)
        let owner = captureActivityID
        let activity = audioCaptureActivity
        Task { @MainActor in activity?.setActive(false, owner: owner) }
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
        keptPartialTakeURL = nil
        activeTakeURL = nil
        handoffWarningMessage = nil
        showSaveConfirmation = false

        let maxDuration: TimeInterval? = maxDurationMinutes > 0
            ? TimeInterval(maxDurationMinutes * 60)
            : nil

        // One settings snapshot supplies both the folder and its protected
        // roots. Unreadable settings must never fall back to defaults: those
        // carry no protected roots, so the guard would allow everything.
        let destination: ToolOutputDestination
        do {
            destination = try destinationProvider()
        } catch {
            presentFailure(.settingsUnreadable)
            return
        }

        let config = RecordSystemAudioUseCase.Config(
            outputURL: destination.folder,
            preset: .cubaseDefault,
            maxDuration: maxDuration,
            filenameOverride: filenameOverride.isEmpty ? nil : filenameOverride,
            outputGuard: destination.outputGuard
        )
        let fileURL: URL
        do {
            fileURL = try useCase.prepareOutputURL(config: config)
        } catch let recorderError as RecorderError {
            presentFailure(recorderError)
            return
        } catch let guardError as OutputWriteGuardError {
            presentFailure(RecorderError.outputRefused(guardError.localizedDescription))
            return
        } catch {
            presentFailure(RecorderError.writeError(error.localizedDescription))
            return
        }

        activeTakeURL = fileURL
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
                    // The recording task already holds self; a separate task keeps
                    // stopRecording from awaiting the task it runs in.
                    Task { @MainActor in
                        await self.stopRecording()
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
        let wasStarting = recordingState == .starting
        stoppingBeforeCapture = wasStarting
        defer { stoppingBeforeCapture = false }
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
            if awaitingCurrentTask {
                await taskToAwait?.value
            }
            recordingTask = nil
            currentLevel = nil
            if wasStarting {
                presentFailure(.apiError("Recording was stopped during startup. If macOS asked for system-audio permission, answer the prompt, then start a new recording."))
            } else {
                recordingState = .idle
                error = nil
            }
        } catch let recorderError as RecorderError {
            // The take stays registered for quit until its task has unwound (ADR-019).
            taskToAwait?.cancel()
            if awaitingCurrentTask {
                await taskToAwait?.value
            }
            recordingTask = nil
            presentFailure(recorderError)
        } catch {
            taskToAwait?.cancel()
            if awaitingCurrentTask {
                await taskToAwait?.value
            }
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

    private static func isActive(_ state: RecordingDisplayState) -> Bool {
        switch state {
        case .starting, .recording, .reconnecting, .stopping: true
        default: false
        }
    }

    /// ADR-019: a take is work quit must not cut off, but not a job, so it
    /// registers unlisted from start until its file is finalized. Quit's
    /// cancel stops the take, which saves it; quit waits for that.
    private func registerTakeForQuit(_ active: Bool) {
        guard let jobStatusCenter else { return }
        guard active else {
            jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.audioRecorder, status: nil)
            return
        }
        jobStatusCenter.setExtraJob(
            sourceID: ShellJobExtraSourceID.audioRecorder,
            status: ShellJobStatus(
                id: ShellJobExtraSourceID.audioRecorder.rawValue,
                title: ShellJobStatusCopy.recordingTake,
                listed: false
            ),
            cancel: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                }
            }
        )
    }

    private func presentFailure(_ recorderError: RecorderError) {
        // A failed take is removed unless it holds written audio, so a file that is
        // still there is the audio recorded before the error.
        keptPartialTakeURL = activeTakeURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        activeTakeURL = nil
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
                    "Recording write failed (\(CountCopy.count(diagnostics.writeErrorCount, "error"))). CoreAudio diagnostics: \(diagnostics.summary)."
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
            // A take with written frames cannot be recorded again: keep it for recovery,
            // out of the inbox, and say where. Only an empty take is removed.
            guard result.frameCount > 0,
                  FileManager.default.fileExists(atPath: result.outputURL.path)
            else {
                try? FileManager.default.removeItem(at: result.outputURL)
                throw error
            }
            throw Self.notingKeptPartialTake(at: result.outputURL, in: error)
        }

        let item = OutputInboxItem(
            id: UUID(),
            fileURL: result.outputURL,
            sourceToolID: .audioRecorder,
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
        activeTakeURL = nil
        showSaveConfirmation = true
        recordingState = .idle
        elapsedTime = 0
        currentLevel = nil
        refreshProposedFilename()
        HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.recordingStopped)
        recentOutputs.refresh()
        if result.silentBecauseCaptureWasBlocked {
            // The take is kept (and handed off) like any other; the card explains why
            // it is silent.
            savedRecordingIsSilentFromBlockedCapture = true
            error = .permissionDenied
            recordingState = .permissionNeeded
        }
    }

    private static func notingKeptPartialTake(at url: URL, in error: Error) -> RecorderError {
        let note = RecorderPCMWriterPipeline.keptPartialTakeNote(url)
        switch error as? RecorderError {
        case .writeError(let message)?:
            return .writeError("\(message) \(note)")
        case .verificationFailed(let message)?:
            return .verificationFailed("\(message) \(note)")
        case .noAudioCaptured(let message)?:
            return .noAudioCaptured("\(message) \(note)")
        default:
            return .verificationFailed("\(error.localizedDescription) \(note)")
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
        keptPartialTakeURL = nil
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
        recentOutputs.refresh()
    }

    private static func handoffWarningMessage(for error: Error) -> String {
        "Recording saved, but Output Inbox could not save the handoff. \(error.localizedDescription)"
    }
}
