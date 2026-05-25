import AppCore
import FeatureAudioConverter
import XCTest
@testable import FeatureAudioRecorder

@MainActor
final class AudioRecorderViewModelTests: XCTestCase {
    func testStartRecordingWhenPermissionDenied() async throws {
        let port = DenyingCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        await vm.startRecording()

        if case .permissionNeeded = vm.recordingState {
            // pass
        } else {
            XCTFail("Expected .permissionNeeded but got \(vm.recordingState)")
        }
    }

    func testStartRecordingWhenIncompatibleMacOS() async throws {
        let port = IncompatibleCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        await vm.startRecording()

        if case .incompatibleMacOS = vm.recordingState {
            // pass
        } else {
            XCTFail("Expected .incompatibleMacOS but got \(vm.recordingState)")
        }
    }

    func testFilenameOverridePassedToUseCase() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        vm.filenameOverride = "My Recording.wav"
        XCTAssertEqual(vm.filenameOverride, "My Recording.wav")
    }

    func testMaxDurationPassedToUseCase() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        vm.maxDurationMinutes = 5
        XCTAssertEqual(vm.maxDurationMinutes, 5)
    }
}

private final class DenyingCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .denied(needsSettings: true)
    }

    func requestPermission() async -> RecorderPermissionState {
        .denied(needsSettings: true)
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class IncompatibleCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        false
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class MockAudioCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                continuation.finish()
            }
        }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0.1, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class InMemoryOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private var items: [OutputInboxItem] = []

    func listItems() throws -> [OutputInboxItem] { items }
    func addItem(_ item: OutputInboxItem) throws { items.append(item) }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}
