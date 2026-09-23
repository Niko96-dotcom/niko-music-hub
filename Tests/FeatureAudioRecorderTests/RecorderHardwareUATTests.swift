import AppCore
import AVFAudio
import Combine
import XCTest
@testable import FeatureAudioRecorder

final class RecorderHardwareUATTests: XCTestCase {
    @MainActor
    func testLiveRouteProducesAudibleVerifiedWAV() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RECORDER_HARDWARE_UAT"] == "1" else {
            throw XCTSkip("Set RECORDER_HARDWARE_UAT=1 to exercise the live system-audio route")
        }

        let route = environment["RECORDER_HARDWARE_ROUTE"] ?? "unknown"
        let duration = TimeInterval(environment["RECORDER_HARDWARE_DURATION"] ?? "5") ?? 5
        let expectsSignal = environment["RECORDER_HARDWARE_EXPECT_SIGNAL"] == "1"
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-recorder-hardware-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let adapter = CoreAudioTapAdapter()
        try await requireHardwareRecordingPermission(adapter)
        let capturePort = ResultCapturingCapturePort(base: adapter)
        let inbox = HardwareUATInboxStore()
        let viewModel = AudioRecorderViewModel(
            capturePort: capturePort,
            useCase: RecordSystemAudioUseCase(capturePort: capturePort),
            outputURL: outputDirectory,
            outputInboxStore: inbox
        )
        await viewModel.startRecording()
        for await state in viewModel.$recordingState.values {
            if state == .recording { break }
            if case .error(let error) = state { throw error }
        }
        try await Task.sleep(for: .seconds(duration))
        await viewModel.stopRecording()

        let result = try XCTUnwrap(capturePort.lastResult)
        let items = try inbox.listItems()
        let outputURL = try XCTUnwrap(items.first?.fileURL)

        let specification = try WAVOutputVerifier().verify(
            url: outputURL,
            expectedSpec: WAVOutputSpec(sampleRate: 44_100, bitDepth: 24, channelCount: 2)
        )
        let peak = try peakMagnitude(in: outputURL)
        let backend = result.diagnostics?.selectedBackend ?? "unknown"
        let diagnostics = result.diagnostics?.summary ?? "none"

        XCTAssertGreaterThan(result.frameCount, 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(viewModel.lastRecordedURL, outputURL)
        XCTAssertEqual(specification.sampleRate, 44_100)
        XCTAssertEqual(specification.bitDepth, 24)
        XCTAssertEqual(specification.channelCount, 2)
        if expectsSignal {
            XCTAssertGreaterThan(peak, 0.000_1, "Expected audible PCM on route \(route)")
        }

        print(
            "RECORDER_HARDWARE_UAT "
                + "route=\(route) frames=\(result.frameCount) backend=\(backend) "
                + "peak=\(peak) diagnostics=\(diagnostics)"
        )
    }

    func testLiveScreenCaptureKitFallbackProducesAudibleVerifiedWAV() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RECORDER_HARDWARE_FALLBACK_UAT"] == "1" else {
            throw XCTSkip("Set RECORDER_HARDWARE_FALLBACK_UAT=1 to exercise real ScreenCaptureKit audio")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-recorder-sck-hardware-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let session = ResilientSystemAudioRecordingSession(
            configuration: RecorderRecoveryConfiguration(
                startupTimeout: .milliseconds(250),
                routeDebounce: .milliseconds(50)
            ),
            coreAudioFactory: { AlwaysFailingCoreBackend() },
            screenCaptureKitFactory: { ScreenCaptureKitAudioSession() }
        )

        try await session.start(
            outputURL: outputURL,
            preset: .cubaseDefault,
            maxDuration: nil,
            onLevel: { _ in },
            onEnded: {}
        )
        try await Task.sleep(for: .seconds(5))
        let result = try await session.stop()
        let specification = try WAVOutputVerifier().verify(
            url: outputURL,
            expectedSpec: WAVOutputSpec(sampleRate: 44_100, bitDepth: 24, channelCount: 2)
        )
        let peak = try peakMagnitude(in: outputURL)

        XCTAssertGreaterThan(result.frameCount, 0)
        XCTAssertEqual(result.diagnostics?.selectedBackend, "screen-capture-kit")
        XCTAssertEqual(result.diagnostics?.screenCaptureKitFallbackCount, 1)
        XCTAssertGreaterThan(peak, 0.000_1)
        XCTAssertEqual(specification, WAVOutputSpec(sampleRate: 44_100, bitDepth: 24, channelCount: 2))
        let backend = result.diagnostics?.selectedBackend ?? "unknown"
        let diagnostics = result.diagnostics?.summary ?? "none"
        print(
            "RECORDER_HARDWARE_FALLBACK_UAT frames=\(result.frameCount) "
                + "backend=\(backend) peak=\(peak) diagnostics=\(diagnostics)"
        )
    }

    /// Host-only: toggle the test host's System Audio Recording grant, then set
    /// RECORDER_PERMISSION_PROBE_EXPECT=authorized|blocked to check the live verdict.
    func testLivePermissionProbeVerdict() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RECORDER_PERMISSION_PROBE_UAT"] == "1" else {
            throw XCTSkip("Set RECORDER_PERMISSION_PROBE_UAT=1 to run the live system-audio permission probe")
        }
        let outcome = await SystemAudioCapturePermissionProbe().probe()
        let verdict = outcome.verdict
        print(
            "RECORDER_PERMISSION_PROBE_UAT verdict=\(verdict) stage=\(outcome.stage) "
                + "evidence=\(outcome.evidence)"
        )
        switch environment["RECORDER_PERMISSION_PROBE_EXPECT"] {
        case "authorized": XCTAssertEqual(verdict, .authorized)
        case "blocked": XCTAssertEqual(verdict, .blocked)
        default: break
        }
    }
}

private final class AlwaysFailingCoreBackend: RecorderCaptureBackend, Sendable {
    let identity = RecorderCaptureBackendIdentity.coreAudio

    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws {
        throw RecorderError.apiError("hardware UAT forced Core Audio startup failure")
    }

    func stop() async {}
}

/// The real adapter owns its lifecycle synchronization; this lock only snapshots the final
/// immutable result so the hardware probe can report backend diagnostics after VM handoff.
private final class ResultCapturingCapturePort: AudioCapturePort, @unchecked Sendable {
    private let base: AudioCapturePort
    private let lock = NSLock()
    private var storedResult: RecorderResult?

    init(base: AudioCapturePort) {
        self.base = base
    }

    var recording: Bool { base.recording }

    var lastResult: RecorderResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func checkPermission() async -> RecorderPermissionState {
        await base.checkPermission()
    }

    func requestPermission() async -> RecorderPermissionState {
        await base.requestPermission()
    }

    func isCompatibleMacOS() -> Bool {
        base.isCompatibleMacOS()
    }

    func startRecording(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?
    ) async throws -> AsyncStream<RecorderAudioLevel> {
        try await base.startRecording(outputURL: outputURL, preset: preset, maxDuration: maxDuration)
    }

    func stopRecording() async throws -> RecorderResult {
        let result = try await base.stopRecording()
        lock.withLock { storedResult = result }
        return result
    }
}

/// Hardware UAT calls may arrive from the recorder task and the main test actor; the lock
/// confines the mutable inbox snapshot to this test-only store.
private final class HardwareUATInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OutputInboxItem] = []

    func listItems() throws -> [OutputInboxItem] {
        lock.withLock { items }
    }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock { items.append(item) }
    }

    func updateItem(_ item: OutputInboxItem) throws {
        lock.withLock {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index] = item
        }
    }

    func refreshAvailability() throws {}
}

private func requireHardwareRecordingPermission(_ adapter: CoreAudioTapAdapter) async throws {
    let state = await adapter.checkPermission()
    guard case .authorized = state else {
        throw XCTSkip("System audio recording permission required; current state: \(state)")
    }
}

private func peakMagnitude(in url: URL) throws -> Float {
    let file = try AVAudioFile(forReading: url)
    let capacity = AVAudioFrameCount(file.length)
    guard capacity > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity)
    else {
        return 0
    }

    try file.read(into: buffer)
    guard let channels = buffer.floatChannelData else { return 0 }

    var peak: Float = 0
    for channel in 0 ..< Int(buffer.format.channelCount) {
        for frame in 0 ..< Int(buffer.frameLength) {
            peak = max(peak, abs(channels[channel][frame]))
        }
    }
    return peak
}
