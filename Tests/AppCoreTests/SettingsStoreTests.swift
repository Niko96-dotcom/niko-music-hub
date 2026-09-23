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

    func testSetupAssistantShownDecodesMissingAsFalse() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertFalse(settings.setupAssistantShown)
    }

    func testSetupAssistantShownRoundTrips() throws {
        var settings = AppSettings.default
        XCTAssertFalse(settings.setupAssistantShown)
        settings.setupAssistantShown = true

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertTrue(decoded.setupAssistantShown)
    }

    func testCorruptVaultSpaceIntentBlocksUnrelatedUpdateAndPreservesBlob() throws {
        // Both a bogus string and an explicit null are present-malformed intents.
        let intents = [#""bogus""#, #"123"#, #"null"#]
        for intent in intents {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            // S1: pins and confirmations must survive an unrelated edit attempt.
            let corrupt = """
            {
              "appearance": "light",
              "vault": {
                "isEnabled": true,
                "rolloutStage": "friends",
                "spaceIntent": \(intent),
                "independentBackupConfirmed": true,
                "keepLocalProjectIDs": ["song-a", "song-b"]
              }
            }
            """
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "intent must throw: \(intent)")
            XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark }, "intent: \(intent)")
            XCTAssertThrowsError(try store.updateSettings { $0.showMenuBarExtra = false }, "intent: \(intent)")

            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for intent: \(intent)")
            XCTAssertTrue(String(data: before, encoding: .utf8)!.contains("song-a"))
            // Fail-closed: the corrupt intent never decodes, so it can never be
            // read as free-space permission.
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    VaultSettings.self,
                    from: Data(#"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":\#(intent)}"#.utf8)
                )
            )
        }
    }

    func testPresentNullVaultFieldsBlockUnrelatedUpdateAndPreserveBlob() throws {
        let vaultPayloads = [
            #"{"isEnabled":null,"rolloutStage":"privateBeta","independentBackupConfirmed":true,"keepLocalProjectIDs":["song-a"]}"#,
            #"{"isEnabled":true,"automaticArchiving":null,"independentBackupConfirmed":true,"keepLocalProjectIDs":["song-a"]}"#,
            #"{"isEnabled":true,"rolloutStage":"privateBeta","independentBackupConfirmed":null,"keepLocalProjectIDs":["song-a"]}"#,
            #"{"isEnabled":true,"rolloutStage":"privateBeta","independentBackupConfirmed":true,"keepLocalProjectIDs":null}"#,
            #"{"isEnabled":true,"inactivityDays":null,"independentBackupConfirmed":true,"keepLocalProjectIDs":["song-a"]}"#,
            #"{"isEnabled":true,"launchAtLogin":null,"independentBackupConfirmed":true,"keepLocalProjectIDs":["song-a"]}"#,
            #"{"isEnabled":true,"rolloutStage":null,"independentBackupConfirmed":true,"keepLocalProjectIDs":["song-a"]}"#,
        ]
        for vault in vaultPayloads {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            let corrupt = #"{"appearance":"light","vault":\#(vault)}"#
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "vault must throw: \(vault)")
            XCTAssertThrowsError(
                try store.updateSettings { $0.appearance = .dark },
                "unrelated edit must throw and preserve blob: \(vault)"
            )
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for: \(vault)")
        }
    }

    func testCorruptHelperToolsBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data(#"{"helperTools":{"ffmpeg":123},"appearance":"light"}"#.utf8), forKey: "nikoMusicHub.settings")
        let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
        XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark })
        XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before)
    }

    func testCorruptMusicRootsBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data(#"{"musicRoots":"bogus","appearance":"light"}"#.utf8), forKey: "nikoMusicHub.settings")
        let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
        XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark })
        XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before)
    }

    func testCorruptLegacyArchiveRootsBlocksUnrelatedUpdate() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data(#"{"archiveRoots":"bogus"}"#.utf8), forKey: "nikoMusicHub.settings")
        let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
        XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark })
        XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before)
    }

    func testCorruptOutputFolderBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.set(Data(#"{"outputFolder":"bogus","appearance":"light"}"#.utf8), forKey: "nikoMusicHub.settings")
        let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

        XCTAssertThrowsError(try store.loadSettings())
        XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark })
        XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before)
    }

    func testCorruptScalarFieldsBlockUnrelatedUpdateAndPreservesBlob() throws {
        let payloads = [
            #"{"maxRecordingDurationMinutes":"bogus"}"#,
            #"{"appearance":"bogus"}"#,
            #"{"appearance":null}"#,
            #"{"showMenuBarExtra":"bogus"}"#,
            #"{"scanExclusionTerms":123}"#,
            #"{"archiveOnboardingCompleted":"bogus"}"#,
            #"{"setupAssistantShown":123}"#,
            #"{"audioPreset":"bogus"}"#,
            #"{"vault":"bogus"}"#,
        ]
        for payload in payloads {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            userDefaults.set(Data(payload.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "payload must throw: \(payload)")
            XCTAssertThrowsError(
                try store.updateSettings { $0.appearance = .dark },
                "unrelated edit must throw and preserve blob: \(payload)"
            )
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for: \(payload)")
        }
    }

    func testMissingKeysStillDecodeToHistoricalDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.audioPreset, .cubaseDefault)
        XCTAssertEqual(settings.helperTools, HelperToolSettings())
        XCTAssertEqual(settings.maxRecordingDurationMinutes, 30)
        XCTAssertEqual(settings.musicRoots, [])
        XCTAssertEqual(settings.vault, VaultSettings())
        XCTAssertEqual(settings.appearance, .followSystem)
        XCTAssertFalse(settings.archiveOnboardingCompleted)
        XCTAssertEqual(settings.scanExclusionTerms, "")
        XCTAssertTrue(settings.showMenuBarExtra)
        XCTAssertFalse(settings.setupAssistantShown)
        XCTAssertTrue(settings.outputFolder.url.path.contains("Niko Music Hub/Inbox"))
    }

    func testValidSettingsRoundTripAndUnrelatedUpdate() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        try store.updateSettings {
            $0.appearance = .light
            $0.showMenuBarExtra = false
            $0.maxRecordingDurationMinutes = 45
        }
        let loaded = try makeStore(suiteName: suiteName).loadSettings()
        XCTAssertEqual(loaded.appearance, .light)
        XCTAssertFalse(loaded.showMenuBarExtra)
        XCTAssertEqual(loaded.maxRecordingDurationMinutes, 45)

        try store.updateSettings { $0.appearance = .dark }
        let reloaded = try makeStore(suiteName: suiteName).loadSettings()
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertFalse(reloaded.showMenuBarExtra, "unrelated field must survive a valid edit")
        XCTAssertEqual(reloaded.maxRecordingDurationMinutes, 45)
    }

    func testCorruptAudioPresetSampleRateBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let intents = [#""bogus""#, #"null"#]
        for intent in intents {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            let corrupt = """
            {"appearance":"light","audioPreset":{"sampleRate":\(intent),"bitDepth":24,"channelCount":2,"channelMode":"preserveMonoStereo"}}
            """
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "sampleRate must throw: \(intent)")
            XCTAssertThrowsError(
                try JSONDecoder().decode(AudioPreset.self, from: Data(#"{"sampleRate":\#(intent),"bitDepth":24,"channelCount":2,"channelMode":"preserveMonoStereo"}"#.utf8)),
                "direct preset decode must throw: \(intent)"
            )
            XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark }, "intent: \(intent)")
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for intent: \(intent)")
        }
    }

    func testCorruptAudioPresetBitDepthBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let intents = [#""bogus""#, #"null"#]
        for intent in intents {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            let corrupt = """
            {"appearance":"light","audioPreset":{"sampleRate":44100,"bitDepth":\(intent),"channelCount":2,"channelMode":"preserveMonoStereo"}}
            """
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "bitDepth must throw: \(intent)")
            XCTAssertThrowsError(
                try JSONDecoder().decode(AudioPreset.self, from: Data(#"{"sampleRate":44100,"bitDepth":\#(intent),"channelCount":2,"channelMode":"preserveMonoStereo"}"#.utf8)),
                "direct preset decode must throw: \(intent)"
            )
            XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark }, "intent: \(intent)")
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for intent: \(intent)")
        }
    }

    func testCorruptAudioPresetChannelCountBlocksUnrelatedUpdateAndPreservesBlob() throws {
        let intents = [#""bogus""#, #"null"#]
        for intent in intents {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            let corrupt = """
            {"appearance":"light","audioPreset":{"sampleRate":44100,"bitDepth":24,"channelCount":\(intent),"channelMode":"preserveMonoStereo"}}
            """
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "channelCount must throw: \(intent)")
            XCTAssertThrowsError(
                try JSONDecoder().decode(AudioPreset.self, from: Data(#"{"sampleRate":44100,"bitDepth":24,"channelCount":\#(intent),"channelMode":"preserveMonoStereo"}"#.utf8)),
                "direct preset decode must throw: \(intent)"
            )
            XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark }, "intent: \(intent)")
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for intent: \(intent)")
        }
    }

    func testCorruptAudioPresetChannelModeBlocksUnrelatedUpdateAndPreservesBlob() throws {
        // A present bogus enum string, a wrong-typed number, and an explicit
        // null must all throw rather than silently fall back to the default.
        let intents = [#""bogus""#, #"123"#, #"null"#]
        for intent in intents {
            let suiteName = uniqueSuiteName()
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            let corrupt = """
            {"appearance":"light","audioPreset":{"sampleRate":44100,"bitDepth":24,"channelCount":2,"channelMode":\(intent)}}
            """
            userDefaults.set(Data(corrupt.utf8), forKey: "nikoMusicHub.settings")
            let before = try XCTUnwrap(userDefaults.data(forKey: "nikoMusicHub.settings"))
            let store = UserDefaultsSettingsStore(userDefaults: userDefaults)

            XCTAssertThrowsError(try store.loadSettings(), "channelMode must throw: \(intent)")
            XCTAssertThrowsError(
                try JSONDecoder().decode(AudioPreset.self, from: Data(#"{"sampleRate":44100,"bitDepth":24,"channelCount":2,"channelMode":\#(intent)}"#.utf8)),
                "direct preset decode must throw: \(intent)"
            )
            XCTAssertThrowsError(try store.updateSettings { $0.appearance = .dark }, "intent: \(intent)")
            XCTAssertEqual(userDefaults.data(forKey: "nikoMusicHub.settings"), before, "blob changed for intent: \(intent)")
        }
    }

    func testAudioPresetMissingKeysKeepLegacyDefaultsAndMigration() throws {
        let empty = try JSONDecoder().decode(AudioPreset.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .cubaseDefault)

        let missingSampleRate = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"bitDepth":16,"channelCount":1,"channelMode":"mono"}"#.utf8)
        )
        XCTAssertEqual(missingSampleRate.sampleRate, 44100)
        XCTAssertEqual(missingSampleRate.bitDepth, 16)

        let missingBitDepth = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"sampleRate":48000,"channelCount":2,"channelMode":"preserveMonoStereo"}"#.utf8)
        )
        XCTAssertEqual(missingBitDepth.sampleRate, 48000)
        XCTAssertEqual(missingBitDepth.bitDepth, 24)

        // Legacy channelCount-to-mode migration when the mode key is absent.
        let monoByCount = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"sampleRate":48000,"bitDepth":16,"channelCount":1}"#.utf8)
        )
        XCTAssertEqual(monoByCount.channelCount, 1)
        XCTAssertEqual(monoByCount.channelMode, .mono)

        let stereoByCount = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"sampleRate":48000,"bitDepth":16,"channelCount":2}"#.utf8)
        )
        XCTAssertEqual(stereoByCount.channelMode, .preserveMonoStereo)

        // Missing channelCount derives from the present mode.
        let countFromMono = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"sampleRate":44100,"bitDepth":24,"channelMode":"mono"}"#.utf8)
        )
        XCTAssertEqual(countFromMono.channelCount, 1)
        XCTAssertEqual(countFromMono.channelMode, .mono)

        let countFromStereo = try JSONDecoder().decode(
            AudioPreset.self,
            from: Data(#"{"sampleRate":44100,"bitDepth":24,"channelMode":"stereo"}"#.utf8)
        )
        XCTAssertEqual(countFromStereo.channelCount, 2)
        XCTAssertEqual(countFromStereo.channelMode, .stereo)
    }

    func testValidAudioPresetRoundTripsAndSurvivesUnrelatedUpdate() throws {
        let preset = AudioPreset(sampleRate: 48000, bitDepth: 16, channelCount: 1, channelMode: .mono)
        let decoded = try JSONDecoder().decode(AudioPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)

        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        try store.updateSettings { $0.audioPreset = preset }
        try store.updateSettings { $0.appearance = .dark }
        let reloaded = try makeStore(suiteName: suiteName).loadSettings()
        XCTAssertEqual(reloaded.audioPreset, preset)
        XCTAssertEqual(reloaded.appearance, .dark)
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
