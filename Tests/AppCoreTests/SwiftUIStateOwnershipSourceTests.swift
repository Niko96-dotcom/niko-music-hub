import XCTest

final class SwiftUIStateOwnershipSourceTests: XCTestCase {
    func testAppObservesOnlySceneStructuralShellState() throws {
        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")

        XCTAssertTrue(app.contains("@StateObject private var menuBarExtra: MenuBarExtraState"))
        XCTAssertFalse(app.contains("@StateObject private var shellSession"))
        XCTAssertTrue(app.contains(".defaultAppStorage(composition.userDefaults)"))
        XCTAssertFalse(app.contains("static var services"))
    }

    func testInjectedFeatureViewModelsAreObservedNotOwned() throws {
        let files = [
            "Sources/FeatureAudioConverter/AudioConverterView.swift",
            "Sources/FeatureAudioRecorder/AudioRecorderView.swift",
            "Sources/FeatureBPMTapper/BPMTapperView.swift",
            "Sources/FeatureDownloader/DownloaderView.swift",
            "Sources/FeatureStemSeparation/StemSeparationView.swift",
        ]

        for file in files {
            let source = try SourceTestSupport.read(file)
            XCTAssertTrue(source.contains("@ObservedObject private var viewModel"), file)
            XCTAssertFalse(source.contains("StateObject(wrappedValue: viewModel)"), file)
        }
    }

    func testToolSelectionAndSettingsRoutingHaveSingleOwners() throws {
        let shell = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        let router = try SourceTestSupport.read("Sources/AppCore/QuickAccess/QuickAccessRouter.swift")
        let settingsPane = try SourceTestSupport.read("Sources/AppCore/Settings/HubSettingsPane.swift")

        XCTAssertTrue(shell.contains("shellSession.selectedToolID"))
        XCTAssertFalse(shell.contains("@State private var selectedToolID"))
        XCTAssertTrue(router.contains("QuickAccessToolRequest"))
        XCTAssertFalse(router.contains("clearSelectedToolID"))
        XCTAssertFalse(settingsPane.contains("hubOpenSettingsPane"))
        XCTAssertFalse(settingsPane.contains("hubOpenSettingsHelpers"))
    }

    func testWindowAndArchiveShortcutsAreScopedToVisibleContext() throws {
        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        let cancelCommands = try SourceTestSupport.read(
            "Sources/NikoMusicHub/Commands/HubCancelCommands.swift"
        )
        let archive = try SourceTestSupport.read(
            "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift"
        )
        let policy = try SourceTestSupport.read(
            "Sources/FeatureArchiveBrowser/ArchiveShortcutFocusPolicy.swift"
        )

        // Close / Minimize are the system items (key-window aware); the one
        // custom window command (⌃⌘F) acts on the key window and the
        // process-wide key monitor is gone.
        let windowCommands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubWindowCommandGroup.swift")
        XCTAssertTrue(windowCommands.contains("NSApp.keyWindow?.toggleFullScreen"))
        XCTAssertFalse(windowCommands.contains("keyboardShortcut(\"w\")"))
        XCTAssertFalse(windowCommands.contains("addLocalMonitorForEvents"))
        XCTAssertTrue(app.contains("NSFullScreenMenuItemEverywhere"))
        XCTAssertFalse(app.contains("addLocalMonitorForEvents"))
        XCTAssertTrue(cancelCommands.contains("@FocusedValue(\\.hubShellCancelContext)"))
        XCTAssertTrue(archive.contains("@Environment(\\.hubToolIsActive)"))
        XCTAssertTrue(archive.contains(".focusedSceneValue(\\.archiveSongActions"))
        XCTAssertTrue(policy.contains("isMainWindow(window)"))
        XCTAssertTrue(policy.contains("isTextEditing(window.firstResponder)"))
    }
}
