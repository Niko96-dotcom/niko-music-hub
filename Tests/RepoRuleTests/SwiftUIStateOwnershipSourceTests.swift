import XCTest

/// SwiftUI state-ownership guards. Structural checks read code with comments and literals blanked;
/// literal-dependent checks read code with only comments blanked, so `"…"` survives while `//` spoofs
/// do not. Wrapper + type/name are tied within one property declaration by `SourceLex`'s predicates
/// (anchored to the first `var`, bound to its declaration, multiline allowed), which
/// `ContractScannerRegressionTests` exercises. Limits: only `var name: Type` and `var name = Type(`
/// forms are reported. AGENTS.md row "SwiftUI state"; docs/architecture.md § SwiftUI state ownership.
final class SwiftUIStateOwnershipSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "SwiftUI state",
        why: "An App that observes the shell session re-evaluates every scene (the LAUNCH-HANG loops); a second owner of the selection or a snapshot of settings goes stale",
        see: "AGENTS.md row \"SwiftUI state\"; docs/architecture.md § SwiftUI state ownership",
        fix: "Observe only scene-structural state in the App, read the session's selection, observe settings through ToolContext.appSettings"
    )

    private static let app = "Sources/NikoMusicHub/NikoMusicHubApp.swift"

    private static let featureViewModels: [(file: String, type: String)] = [
        ("Sources/FeatureAudioConverter/AudioConverterView.swift", "AudioConverterViewModel"),
        ("Sources/FeatureAudioRecorder/AudioRecorderView.swift", "AudioRecorderViewModel"),
        ("Sources/FeatureBPMTapper/BPMTapperView.swift", "BPMTapperViewModel"),
        ("Sources/FeatureDownloader/DownloaderView.swift", "DownloaderViewModel"),
        ("Sources/FeatureStemSeparation/StemSeparationView.swift", "StemSeparationViewModel"),
    ]

    func testAppObservesOnlySceneStructuralShellState() {
        let app = SourceTree.read(Self.app, .code)
        let declarations = SourceLex.propertyDeclarations(in: app)
        Self.rule.require(SourceLex.declaresStateObject(ofType: "MenuBarExtraState", in: app), "the App no longer @StateObjects MenuBarExtraState")
        Self.rule.require(SourceLex.declaresStateObject(ofType: "AppAppearanceController", in: app), "the App no longer @StateObjects AppAppearanceController")
        for wrapper in ["StateObject", "ObservedObject", "State", "EnvironmentObject"] {
            Self.rule.require(!declarations.contains { $0.wrapper == wrapper && $0.type == "HubShellSession" }, "the App observes HubShellSession via @\(wrapper)")
        }
        Self.rule.require(!declarations.contains { ["StateObject", "ObservedObject", "State"].contains($0.wrapper) && $0.name == "shellSession" },
                          "the App wraps shellSession in a property wrapper")
        Self.rule.require(SourceLex.hasCompositionDefaultAppStorage(in: app),
                          "@AppStorage no longer reads the composition's defaults suite (.defaultAppStorage(composition.userDefaults))")
        Self.rule.require(app.range(of: "static\\s+var\\s+services\\b", options: .regularExpression) == nil,
                          "the App delegate's services are static; they are instance state")
        let unexpected = SourceLex.unexpectedObservedTypes(in: app, allowed: ["MenuBarExtraState", "AppAppearanceController", "HubFullScreenState"])
        Self.rule.require(unexpected.isEmpty, "the App observes \(unexpected), not only MenuBarExtraState, AppAppearanceController and HubFullScreenState")
    }

    func testInjectedFeatureViewModelsAreObservedNotOwned() {
        for (file, type) in Self.featureViewModels {
            let source = SourceTree.read(file, .code)
            Self.rule.require(SourceLex.declaresObservedObject(ofType: type, in: source), "\(file): the injected \(type) is not @ObservedObject")
            Self.rule.require(!SourceLex.declaresStateObject(ofType: type, in: source), "\(file): the session-owned \(type) is a @StateObject")
            Self.rule.require(!SourceLex.hasStateObjectInit(wrapping: type, in: source), "\(file): builds a StateObject wrapping \(type)")
            Self.rule.require(!SourceLex.hasUnderscoreStateObjectInit(for: SourceLex.observedPropertyNames(ofType: type, in: source), in: source),
                              "\(file): assigns _<viewModel> = StateObject (an init bypass)")
        }
    }

    func testToolSelectionAndSettingsRoutingHaveSingleOwners() {
        let shellPath = "Sources/NikoMusicHub/AppShell/AppShellView.swift"
        let shell = SourceLex.propertyDeclarations(in: SourceTree.read(shellPath, .code))
        Self.rule.expect(shellPath, matching: "shellSession\\s*\\.\\s*selectedToolID", "a read of the session-owned selectedToolID")
        Self.rule.require(!shell.contains { $0.wrapper == "State" && $0.type == "ToolFeatureID" }, "\(shellPath) holds a @State ToolFeatureID")
        Self.rule.require(!shell.contains { $0.wrapper == "State" && ($0.name == "selectedToolID" || $0.type == "selectedToolID") },
                          "\(shellPath) holds the selection in @State")
        let router = "Sources/AppCore/QuickAccess/QuickAccessRouter.swift"
        Self.rule.expect(router, matching: "\\bQuickAccessToolRequest\\b", "one-shot QuickAccessToolRequest values")
        Self.rule.expect(router, matching: "func\\s+requestSettingsPane\\b", "requestSettingsPane for Settings deep links")
        Self.rule.expect(router, notMatching: "\\bclearSelectedToolID\\b", "clears a selection; router requests are one-shot values")
        let pane = "Sources/AppCore/Settings/HubSettingsPane.swift"
        Self.rule.expect(pane, notMatching: "\\bhubOpenSettingsPane\\b", "routes a Settings pane through NotificationCenter")
        Self.rule.expect(pane, notMatching: "\\bhubOpenSettingsHelpers\\b", "routes the helpers pane through NotificationCenter")
    }

    func testWindowAndArchiveShortcutsAreScopedToVisibleContext() {
        let window = "Sources/NikoMusicHub/Commands/HubWindowCommandGroup.swift"
        Self.rule.expect(window, matching: "NSApp\\s*\\.\\s*keyWindow\\s*\\?\\s*\\.\\s*toggleFullScreen\\s*\\(\\s*nil\\s*\\)", "full screen on the key window")
        Self.rule.expect(window, .codeAndStrings, notMatching: "keyboardShortcut\\s*\\(\\s*\"w\"", "binds ⌘W; Close stays the system item")
        Self.rule.expect(window, notMatching: "\\baddLocalMonitorForEvents\\b", "installs a process-wide key monitor")
        Self.rule.expect(Self.app, .codeAndStrings, matching: "\\bNSFullScreenMenuItemEverywhere\\b", "the suppressed duplicate system full-screen item")
        Self.rule.expect(Self.app, notMatching: "\\baddLocalMonitorForEvents\\b", "installs a process-wide key monitor")
        Self.rule.expect("Sources/NikoMusicHub/Commands/HubCancelCommands.swift", matching: "@\\s*FocusedValue[^;{}]*?hubShellCancelContext",
                         "cancel routing through the focused cancel context")
        let archive = "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift"
        Self.rule.expect(archive, matching: "@\\s*Environment[^;{}]*?hubToolIsActive", "the archive following the active-tool flag")
        Self.rule.expect(archive, matching: "focusedSceneValue[^;{}]*?archiveSongActions", "the Song menu scoped to the visible archive pane")
        let policy = "Sources/FeatureArchiveBrowser/ArchiveShortcutFocusPolicy.swift"
        Self.rule.expect(policy, matching: "\\bisMainWindow\\s*\\(\\s*window\\s*\\)", "the arrow monitor scoped to the main window")
        Self.rule.expect(policy, matching: "\\bisTextEditing\\s*\\(\\s*window\\.firstResponder\\s*\\)", "the arrow monitor yielding to text editing")
    }
}
