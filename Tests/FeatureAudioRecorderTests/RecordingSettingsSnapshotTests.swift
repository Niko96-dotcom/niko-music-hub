import AppCore
import Foundation
import NikoMusicCore
import XCTest
@testable import FeatureAudioRecorder

/// Recording start reads ONE throwing settings snapshot for the destination and
/// its protected roots. Unreadable settings must refuse the start instead of
/// falling back to defaults (which carry no protected roots).
@MainActor
final class RecordingSettingsSnapshotTests: XCTestCase {
    private var tempRoot: URL!
    private var suiteName: String!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        suiteName = "recorder-snapshot-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func testUnreadableSavedSettingsRefuseStartWithoutCaptureOrDirectory() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(Data("not json".utf8), forKey: "nikoMusicHub.settings")
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        XCTAssertThrowsError(try store.loadSettings())

        let defaultInbox = StoredFolderLocation.defaultOutputFolder
        let inboxExistedBefore = FileManager.default.fileExists(atPath: defaultInbox.path)

        let port = CountingCapturePort()
        let vm = makeViewModel(port: port) { try RecordingDestination.load(from: store) }

        await vm.startRecording()

        XCTAssertEqual(port.startedURLs, [])
        XCTAssertEqual(vm.recordingState, .error(.settingsUnreadable))
        XCTAssertEqual(vm.error, .settingsUnreadable)
        XCTAssertEqual(
            vm.error?.errorDescription,
            "Settings couldn’t be read, so recording didn’t start. Repair them in Settings, then try again."
        )
        XCTAssertEqual(FileManager.default.fileExists(atPath: defaultInbox.path), inboxExistedBefore)
    }

    func testThrowingProviderCreatesNoOutputDirectory() async throws {
        let output = tempRoot.appendingPathComponent("Inbox", isDirectory: true)
        let port = CountingCapturePort()
        let vm = makeViewModel(port: port) { throw SnapshotTestError.unreadable }

        await vm.startRecording()

        XCTAssertEqual(port.startedURLs, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(vm.recordingState, .error(.settingsUnreadable))
    }

    func testFirstRunWithNothingSavedStillLoadsDefaultDestination() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let destination = try RecordingDestination.load(from: store)

        XCTAssertEqual(destination.folder, StoredFolderLocation.defaultOutputFolder)
        XCTAssertEqual(destination.protectedRoots, [])
    }

    func testDestinationInsideProtectedRootFromReadableSnapshotIsRefused() async throws {
        let musicRoot = tempRoot.appendingPathComponent("Music", isDirectory: true)
        let inbox = musicRoot.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: musicRoot, withIntermediateDirectories: true)
        let store = FixtureSettingsStore(settings: AppSettings(
            outputFolder: StoredFolderLocation(url: inbox),
            musicRoots: [StoredMusicRoot(role: .scanOnly, url: musicRoot)]
        ))

        let port = CountingCapturePort()
        let vm = makeViewModel(port: port) { try RecordingDestination.load(from: store) }

        await vm.startRecording()

        XCTAssertEqual(port.startedURLs, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
        guard case .error(let error) = vm.recordingState else {
            return XCTFail("Expected .error but got \(vm.recordingState)")
        }
        XCTAssertNotEqual(error, .settingsUnreadable)
    }

    func testReadableSettingsWithUnprotectedDestinationStartCapture() async throws {
        let musicRoot = tempRoot.appendingPathComponent("Music", isDirectory: true)
        let output = tempRoot.appendingPathComponent("Out", isDirectory: true)
        let store = FixtureSettingsStore(settings: AppSettings(
            outputFolder: StoredFolderLocation(url: output),
            musicRoots: [StoredMusicRoot(role: .scanOnly, url: musicRoot)]
        ))

        let port = CountingCapturePort()
        let vm = makeViewModel(port: port) { try RecordingDestination.load(from: store) }

        await vm.startRecording()
        for _ in 0..<200 where port.startedURLs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(port.startedURLs.count, 1)
        XCTAssertEqual(
            port.startedURLs.first?.deletingLastPathComponent().standardizedFileURL.path,
            output.standardizedFileURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeViewModel(
        port: CountingCapturePort,
        destination: @escaping @MainActor () throws -> RecordingDestination
    ) -> AudioRecorderViewModel {
        AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            destinationProvider: destination,
            outputInboxStore: NullOutputInboxStore()
        )
    }
}

private enum SnapshotTestError: Error { case unreadable }

private struct FixtureSettingsStore: SettingsStore {
    var settings: AppSettings
    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

/// Records each start and then fails it, so no audio file or verification is needed.
private final class CountingCapturePort: AudioCapturePort, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var startedURLs: [URL] { lock.withLock { urls } }
    var recording: Bool { false }

    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?
    ) async throws -> AsyncStream<RecorderAudioLevel> {
        lock.withLock { urls.append(outputURL) }
        throw RecorderError.apiError("stub start failure")
    }

    func stopRecording() async throws -> RecorderResult {
        throw RecorderError.apiError("not recording")
    }
}

private final class NullOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}
