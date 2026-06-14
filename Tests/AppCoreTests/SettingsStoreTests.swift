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
        let demucsMlx = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")

        try store.updateSettings { settings in
            settings.helperTools = HelperToolSettings(
                ffmpeg: ffmpeg,
                ffprobe: ffprobe,
                ytDlp: ytDlp,
                demucsMlx: demucsMlx
            )
        }

        let helperTools = try makeStore(suiteName: suiteName, reset: false).loadSettings().helperTools
        XCTAssertEqual(helperTools.ffmpeg, ffmpeg)
        XCTAssertEqual(helperTools.ffprobe, ffprobe)
        XCTAssertEqual(helperTools.ytDlp, ytDlp)
        XCTAssertEqual(helperTools.demucsMlx, demucsMlx)
    }

    func testLoadsLegacySettingsMissingArchiveOnboardingFlag() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let legacyJSON = """
        {
          "helperTools": {},
          "outputFolder": {
            "url": "file:///Users/example/Music/Niko%20Music%20Hub/Inbox/"
          },
          "archiveRoots": [
            { "path": "/Users/example/Music/00_Cubase Project" }
          ],
          "maxRecordingDurationMinutes": 30,
          "audioPreset": {
            "bitDepth": 24,
            "channelCount": 2,
            "channelMode": "preserveMonoStereo",
            "sampleRate": 44100
          }
        }
        """
        userDefaults.set(Data(legacyJSON.utf8), forKey: "nikoMusicHub.settings")

        let settings = try UserDefaultsSettingsStore(userDefaults: userDefaults).loadSettings()

        XCTAssertEqual(settings.outputFolder.url.path, "/Users/example/Music/Niko Music Hub/Inbox")
        XCTAssertEqual(settings.archiveRoots.map(\.path), ["/Users/example/Music/00_Cubase Project"])
        XCTAssertFalse(settings.archiveOnboardingCompleted)
        XCTAssertEqual(settings.audioPreset.sampleRate, 44100)
        XCTAssertEqual(settings.audioPreset.bitDepth, 24)
        XCTAssertEqual(settings.audioPreset.channelMode, .preserveMonoStereo)
    }

    func testCorruptSettingsDataThrows() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data("not-json".utf8), forKey: "nikoMusicHub.settings")

        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
    }

    func testSettingsViewSurfacesLoadErrorsAndBlocksSaveFallback() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("settingsLoadError"))
        XCTAssertTrue(source.contains("Settings were not saved"))
        XCTAssertFalse(source.contains("(try? context.settingsStore.loadSettings()) ?? .default"))
    }

    func testLoadsLegacyAudioPresetMissingChannelMode() throws {
        let data = Data("""
        {
          "sampleRate": 48000,
          "bitDepth": 16,
          "channelCount": 1
        }
        """.utf8)

        let preset = try JSONDecoder().decode(AudioPreset.self, from: data)

        XCTAssertEqual(preset.sampleRate, 48000)
        XCTAssertEqual(preset.bitDepth, 16)
        XCTAssertEqual(preset.channelCount, 1)
        XCTAssertEqual(preset.channelMode, .mono)
    }

    private func makeStore(suiteName: String = UUID().uuidString, reset: Bool = false) -> UserDefaultsSettingsStore {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        if reset {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return UserDefaultsSettingsStore(userDefaults: userDefaults)
    }

    private func uniqueSuiteName() -> String {
        "OutsideCubaseHubTests.\(UUID().uuidString)"
    }
}
