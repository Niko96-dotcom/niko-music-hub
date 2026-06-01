import AppCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettingsUseCubaseReadyOutputFolderAndAudioPreset() throws {
        let store = makeStore()
        let settings = try store.loadSettings()

        XCTAssertTrue(settings.outputFolder.url.path.contains("Niko Music Hub/Inbox"))
        XCTAssertEqual(settings.audioPreset.sampleRate, 44100)
        XCTAssertEqual(settings.audioPreset.bitDepth, 24)
        XCTAssertEqual(settings.audioPreset.channelCount, 2)
        XCTAssertEqual(settings.audioPreset.channelMode, .preserveMonoStereo)
    }

    func testPersistsOutputFolder() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        let folder = URL(fileURLWithPath: "/tmp/custom-outside-cubase")

        try store.updateSettings { settings in
            settings.outputFolder = StoredFolderLocation(url: folder)
        }

        let reloaded = makeStore(suiteName: suiteName)
        XCTAssertEqual(try reloaded.loadSettings().outputFolder.url, folder)
    }

    func testPersistsAudioPresetDefaults() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)

        try store.updateSettings { settings in
            settings.audioPreset = AudioPreset(
                sampleRate: 44100,
                bitDepth: 16,
                channelCount: 1,
                channelMode: .mono
            )
        }

        let reloaded = makeStore(suiteName: suiteName)
        XCTAssertEqual(try reloaded.loadSettings().audioPreset.sampleRate, 44100)
        XCTAssertEqual(try reloaded.loadSettings().audioPreset.bitDepth, 16)
        XCTAssertEqual(try reloaded.loadSettings().audioPreset.channelMode, .mono)
    }

    func testPersistsHelperToolPaths() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let ffprobe = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        let ytDlp = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")

        try store.updateSettings { settings in
            settings.helperTools = HelperToolSettings(
                ffmpeg: ffmpeg,
                ffprobe: ffprobe,
                ytDlp: ytDlp
            )
        }

        let helperTools = try makeStore(suiteName: suiteName, reset: false).loadSettings().helperTools
        XCTAssertEqual(helperTools.ffmpeg, ffmpeg)
        XCTAssertEqual(helperTools.ffprobe, ffprobe)
        XCTAssertEqual(helperTools.ytDlp, ytDlp)
    }

    private func makeStore(suiteName: String = UUID().uuidString, reset: Bool = false) -> UserDefaultsSettingsStore {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        if reset {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return UserDefaultsSettingsStore(userDefaults: userDefaults)
    }

    private func uniqueSuiteName() -> String {
        "NikoMusicHubTests.\(UUID().uuidString)"
    }
}
