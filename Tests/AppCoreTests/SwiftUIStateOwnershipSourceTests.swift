import XCTest

/// SwiftUI state-ownership guards (see AGENTS.md "SwiftUI state ownership").
///
/// Structural checks run over `SourceLex.stripped(_:)` (comments + literals
/// blanked) except literal-dependent guards, which run over
/// `SourceLex.strippedCommentsOnly(_:)` so `"…"` survives while `//` spoofs
/// do not. Wrapper + type/name are tied within one property declaration via
/// shared `SourceLex` predicates anchored to the FIRST `var` and bound to its
/// declaration (multiline allowed, never crossing another `@`/`;`/`{`/`}` or
/// a later `var`/`let`), also exercised by `ContractScannerRegressionTests`.
///
/// Limits: only `var name: Type` and `var name = Type(` forms are reported;
/// other spellings are out of scope.
final class SwiftUIStateOwnershipSourceTests: XCTestCase {
    private func stripped(_ relativePath: String) throws -> String {
        SourceLex.stripped(try SourceTestSupport.read(relativePath))
    }

    private func commentsOnly(_ relativePath: String) throws -> String {
        SourceLex.strippedCommentsOnly(try SourceTestSupport.read(relativePath))
    }

    private let featureViewModels: [(file: String, type: String)] = [
        ("Sources/FeatureAudioConverter/AudioConverterView.swift", "AudioConverterViewModel"),
        ("Sources/FeatureAudioRecorder/AudioRecorderView.swift", "AudioRecorderViewModel"),
        ("Sources/FeatureBPMTapper/BPMTapperView.swift", "BPMTapperViewModel"),
        ("Sources/FeatureDownloader/DownloaderView.swift", "DownloaderViewModel"),
        ("Sources/FeatureStemSeparation/StemSeparationView.swift", "StemSeparationViewModel"),
    ]

    func testAppObservesOnlySceneStructuralShellState() throws {
        let app = try stripped("Sources/NikoMusicHub/NikoMusicHubApp.swift")

        XCTAssertTrue(
            SourceLex.declaresStateObject(ofType: "MenuBarExtraState", in: app),
            "App must @StateObject the MenuBarExtraState (any name, multiline allowed)"
        )
        XCTAssertTrue(
            SourceLex.declaresStateObject(ofType: "AppAppearanceController", in: app),
            "App must @StateObject the AppAppearanceController (any name, multiline allowed)"
        )
        for wrapper in ["StateObject", "ObservedObject", "State", "EnvironmentObject"] {
            XCTAssertFalse(
                SourceLex.propertyDeclarations(in: app).contains { $0.wrapper == wrapper && $0.type == "HubShellSession" },
                "App must never observe HubShellSession via @\(wrapper) (same declaration)"
            )
        }
        XCTAssertFalse(
            SourceLex.propertyDeclarations(in: app).contains { ["StateObject", "ObservedObject", "State"].contains($0.wrapper) && $0.name == "shellSession" },
            "App must never wrap shellSession in the same declaration"
        )
        XCTAssertTrue(
            SourceLex.hasCompositionDefaultAppStorage(in: app),
            "AppStorage must read the composition defaults suite (.defaultAppStorage(composition.userDefaults))"
        )
        XCTAssertNil(
            app.range(of: "static\\s+var\\s+services\\b", options: .regularExpression),
            "App delegate services are instance state, not static"
        )
        // Allowlist limits observed types to structural state.
        XCTAssertEqual(
            SourceLex.unexpectedObservedTypes(
                in: app,
                allowed: ["MenuBarExtraState", "AppAppearanceController", "HubFullScreenState"]
            ),
            [],
            "App may only observe structural state (MenuBarExtraState, AppAppearanceController, HubFullScreenState)"
        )
    }

    func testInjectedFeatureViewModelsAreObservedNotOwned() throws {
        for (file, type) in featureViewModels {
            let source = try stripped(file)
            XCTAssertTrue(
                SourceLex.declaresObservedObject(ofType: type, in: source),
                "\(file): injected \(type) must be @ObservedObject (any name, multiline allowed)"
            )
            XCTAssertFalse(
                SourceLex.declaresStateObject(ofType: type, in: source),
                "\(file): session-owned \(type) must not be @StateObject (unrelated @StateObject allowed)"
            )
            XCTAssertFalse(
                SourceLex.hasStateObjectInit(wrapping: type, in: source),
                "\(file): must not construct StateObject wrapping \(type)"
            )
            let names = SourceLex.observedPropertyNames(ofType: type, in: source)
            XCTAssertFalse(
                SourceLex.hasUnderscoreStateObjectInit(for: names, in: source),
                "\(file): must not assign _<viewModel> = StateObject (covers init bypass)"
            )
        }
    }

    func testToolSelectionAndSettingsRoutingHaveSingleOwners() throws {
        let shell = try stripped("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        let router = try stripped("Sources/AppCore/QuickAccess/QuickAccessRouter.swift")
        let settingsPane = try stripped("Sources/AppCore/Settings/HubSettingsPane.swift")

        XCTAssertNotNil(
            shell.range(of: "shellSession\\s*\\.\\s*selectedToolID", options: .regularExpression),
            "AppShellView must read the session-owned selectedToolID"
        )
        XCTAssertFalse(
            SourceLex.propertyDeclarations(in: shell).contains { $0.wrapper == "State" && $0.type == "ToolFeatureID" },
            "AppShellView must not @State a ToolFeatureID (same declaration)"
        )
        XCTAssertFalse(
            SourceLex.propertyDeclarations(in: shell).contains { $0.wrapper == "State" && ($0.name == "selectedToolID" || $0.type == "selectedToolID") },
            "AppShellView must not @State the selection (same declaration)"
        )
        XCTAssertNotNil(
            router.range(of: "\\bQuickAccessToolRequest\\b", options: .regularExpression),
            "Router tool requests are one-shot QuickAccessToolRequest values"
        )
        XCTAssertNotNil(
            router.range(of: "func\\s+requestSettingsPane\\b", options: .regularExpression),
            "Settings deep links go through router.requestSettingsPane"
        )
        XCTAssertNil(
            router.range(of: "\\bclearSelectedToolID\\b", options: .regularExpression),
            "Router has no clear-selection state to clear (one-shot values)"
        )
        XCTAssertNil(
            settingsPane.range(of: "\\bhubOpenSettingsPane\\b", options: .regularExpression),
            "No NotificationCenter settings-pane routing"
        )
        XCTAssertNil(
            settingsPane.range(of: "\\bhubOpenSettingsHelpers\\b", options: .regularExpression),
            "No NotificationCenter helpers routing"
        )
    }

    func testWindowAndArchiveShortcutsAreScopedToVisibleContext() throws {
        let appStripped = try stripped("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        let appComments = try commentsOnly("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        let cancelCommands = try stripped(
            "Sources/NikoMusicHub/Commands/HubCancelCommands.swift"
        )
        let archive = try stripped(
            "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift"
        )
        let policy = try stripped(
            "Sources/FeatureArchiveBrowser/ArchiveShortcutFocusPolicy.swift"
        )
        let windowCommandsStripped = try stripped("Sources/NikoMusicHub/Commands/HubWindowCommandGroup.swift")
        let windowCommandsComments = try commentsOnly("Sources/NikoMusicHub/Commands/HubWindowCommandGroup.swift")

        XCTAssertNotNil(
            windowCommandsStripped.range(of: "NSApp\\s*\\.\\s*keyWindow\\s*\\?\\s*\\.\\s*toggleFullScreen\\s*\\(\\s*nil\\s*\\)", options: .regularExpression),
            "Full-screen acts on the key window (toggleFullScreen(nil))"
        )
        XCTAssertNil(
            windowCommandsComments.range(of: "keyboardShortcut\\s*\\(\\s*\"w\"", options: .regularExpression),
            "Close stays the system item (no keyboardShortcut(\"w\"))"
        )
        XCTAssertNil(
            windowCommandsStripped.range(of: "\\baddLocalMonitorForEvents\\b", options: .regularExpression),
            "No process-wide key monitor in window commands"
        )
        XCTAssertNotNil(
            appComments.range(of: "\\bNSFullScreenMenuItemEverywhere\\b", options: .regularExpression),
            "App suppresses the duplicate system full-screen item (string literal retained)"
        )
        XCTAssertNil(
            appStripped.range(of: "\\baddLocalMonitorForEvents\\b", options: .regularExpression),
            "No process-wide key monitor in the App"
        )
        XCTAssertNotNil(
            cancelCommands.range(of: "@\\s*FocusedValue[^;{}]*?hubShellCancelContext", options: .regularExpression),
            "Cancel routing reads the focused cancel context"
        )
        XCTAssertNotNil(
            archive.range(of: "@\\s*Environment[^;{}]*?hubToolIsActive", options: .regularExpression),
            "Archive follows the mounted-but-hidden active-tool flag"
        )
        XCTAssertNotNil(
            archive.range(of: "focusedSceneValue[^;{}]*?archiveSongActions", options: .regularExpression),
            "Song menu is scoped to the visible archive pane"
        )
        XCTAssertNotNil(
            policy.range(of: "\\bisMainWindow\\s*\\(\\s*window\\s*\\)", options: .regularExpression),
            "Arrow monitor is scoped to the main window (isMainWindow(window))"
        )
        XCTAssertNotNil(
            policy.range(of: "\\bisTextEditing\\s*\\(\\s*window\\.firstResponder\\s*\\)", options: .regularExpression),
            "Arrow monitor yields to text editing (isTextEditing(window.firstResponder))"
        )
    }
}
