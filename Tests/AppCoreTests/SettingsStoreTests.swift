import AppCore
import Combine
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testUpdatePublishesPersistedSettings() throws {
        let store = makeStore(reset: true)
        var received: AppSettings?
        let subscription = store.settingsChanges.sink { received = $0 }

        try store.updateSettings { $0.maxRecordingDurationMinutes = 45 }

        XCTAssertEqual(received?.maxRecordingDurationMinutes, 45)
        withExtendedLifetime(subscription) {}
    }

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

    func testPersistsAppearancePreference() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)

        try store.updateSettings { settings in
            settings.appearance = .light
        }

        XCTAssertEqual(try makeStore(suiteName: suiteName).loadSettings().appearance, .light)
    }

    func testLoadsLegacySettingsMissingArchiveOnboardingFlag() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let legacyJSON = """
        {
          "helperTools": {},
          "outputFolder": {
            "url": "file:///Users/tester/Music/Niko%20Music%20Hub/Inbox/"
          },
          "archiveRoots": [
            { "path": "/Users/tester/Music/00_Cubase Project" }
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

        XCTAssertEqual(settings.outputFolder.url.path, "/Users/tester/Music/Niko Music Hub/Inbox")
        XCTAssertEqual(settings.archiveRoots.map(\.path), ["/Users/tester/Music/00_Cubase Project"])
        XCTAssertFalse(settings.archiveOnboardingCompleted)
        XCTAssertEqual(settings.appearance, .followSystem)
        XCTAssertEqual(settings.audioPreset.sampleRate, 44100)
        XCTAssertEqual(settings.audioPreset.bitDepth, 24)
        XCTAssertEqual(settings.audioPreset.channelMode, .preserveMonoStereo)
        XCTAssertTrue(settings.showMenuBarExtra)
    }

    func testDefaultSettingsEnableMenuBarExtra() throws {
        let store = makeStore()
        XCTAssertTrue(try store.loadSettings().showMenuBarExtra)
        XCTAssertTrue(AppSettings.default.showMenuBarExtra)
    }

    func testPersistsShowMenuBarExtraOff() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)

        try store.updateSettings { settings in
            settings.showMenuBarExtra = false
        }

        XCTAssertFalse(try makeStore(suiteName: suiteName).loadSettings().showMenuBarExtra)
    }

    func testCorruptSettingsDataThrows() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data("not-json".utf8), forKey: "nikoMusicHub.settings")

        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
    }

    func testConcurrentAtomicUpdatesPreserveUnrelatedFields() throws {
        let suiteName = uniqueSuiteName()
        let storeA = makeStore(suiteName: suiteName, reset: true)
        let storeB = makeStore(suiteName: suiteName)
        let outputURL = URL(fileURLWithPath: "/tmp/concurrent-settings-output")
        let failures = LockedSettingsFailures()

        DispatchQueue.concurrentPerform(iterations: 500) { index in
            do {
                if index.isMultiple(of: 2) {
                    try storeA.updateSettings { settings in
                        settings.outputFolder = StoredFolderLocation(url: outputURL)
                    }
                } else {
                    try storeB.updateSettings { settings in
                        settings.appearance = .dark
                    }
                }
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.isEmpty)
        let reloaded = try storeA.loadSettings()
        XCTAssertEqual(reloaded.outputFolder.url, outputURL)
        XCTAssertEqual(reloaded.appearance, .dark)
    }

    func testSettingsViewSurfacesLoadErrorsAndBlocksSaveFallback() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("settingsLoadError"))
        XCTAssertTrue(source.contains("Settings were not saved"))
        XCTAssertFalse(source.contains("(try? context.settingsStore.loadSettings()) ?? .default"))
        XCTAssertTrue(source.contains("appearanceController.apply(settings.appearance)"))
    }

    func testSettingsDoesNotApplyAppearanceWhenLoadFails() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        guard let applyRange = source.range(of: "appearanceController.apply(settings.appearance)"),
              let catchRange = source.range(of: "} catch {")
        else {
            return XCTFail("Expected appearance apply and catch block in SettingsView.refresh")
        }
        XCTAssertLessThan(applyRange.lowerBound, catchRange.lowerBound)
    }

    func testSettingsAppearanceBindingRevertsOnSaveFailure() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let previous = settings.appearance"))
        XCTAssertTrue(source.contains("appearanceController.apply(previous)"))
    }

    func testSettingsGeneralPaneOffersMenuBarExtraToggle() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Show menu bar extra"))
        XCTAssertTrue(source.contains("showMenuBarExtraBinding"))
    }

    func testSettingsMaxDurationBindingRevertsOnSaveFailure() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let previous = settings.maxRecordingDurationMinutes"))
        XCTAssertTrue(source.contains("settings.maxRecordingDurationMinutes = previous"))
    }

    func testSettingsOutputFolderRevertsOnSaveFailure() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let previous = settings.outputFolder"))
        XCTAssertTrue(source.contains("settings.outputFolder = previous"))
    }

    func testSettingsLaunchAtLoginRollbackKeepsFailureVisible() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("guard enabled != context.launchAtLogin.isEnabled() else { return }")
        )
    }

    func testSettingsNormalizesRecordingDurationOnLoad() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/SettingsView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("RecordingDurationOptions.normalized("))
        XCTAssertTrue(source.contains("RecordingDurationOptions.supportedMinutes"))
    }

    func testNikoMusicHubAppAppliesPreferredColorScheme() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/NikoMusicHubApp.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".preferredColorScheme(appearanceController.preferredColorScheme)"))
    }

    func testAudioRecorderSeedsMaxDurationFromSettings() throws {
        let featureSource = try String(
            contentsOfFile: "Sources/FeatureAudioRecorder/AudioRecorderFeature.swift",
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOfFile: "Sources/FeatureAudioRecorder/AudioRecorderView.swift",
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOfFile: "Sources/FeatureAudioRecorder/AudioRecorderViewModel.swift",
            encoding: .utf8
        )

        XCTAssertTrue(featureSource.contains("initialMaxDurationMinutes"))
        XCTAssertTrue(featureSource.contains("RecordingDurationOptions.normalized(settings.maxRecordingDurationMinutes)"))
        XCTAssertTrue(viewSource.contains("persistMaxDuration"))
        XCTAssertTrue(viewSource.contains("lastPersistedMaxDurationMinutes"))
        XCTAssertTrue(viewSource.contains("syncMaxDurationFromSettings"))
        XCTAssertTrue(modelSource.contains("initialMaxDurationMinutes"))
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

private final class LockedSettingsFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    func append(_ error: any Error) {
        lock.withLock { errors.append(error) }
    }

    var isEmpty: Bool {
        lock.withLock { errors.isEmpty }
    }
}
