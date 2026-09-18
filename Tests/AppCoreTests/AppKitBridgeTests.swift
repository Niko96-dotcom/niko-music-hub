import AppKit
import SwiftUI
import XCTest
@testable import AppCore

/// Contract for the SwiftUI → AppKit bridges: SwiftUI owns the state, AppKit
/// objects stay inside the representable, and no window is held globally.
final class AppKitBridgeTests: XCTestCase {
    @MainActor
    func testVisualEffectViewMirrorsSwiftUIValuesOnly() {
        let active = HubVisualEffectView(material: .sidebar, blending: .behindWindow, isActive: true)
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState

        active.apply(to: view)
        XCTAssertEqual(view.material, .sidebar)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active, "Active state comes from controlActiveState, not from the window")

        // Re-applying the same values is a no-op (LAUNCH-HANG guard).
        active.apply(to: view)
        XCTAssertEqual(view.state, .active)

        HubVisualEffectView(material: .sidebar, blending: .behindWindow, isActive: false).apply(to: view)
        XCTAssertEqual(view.state, .inactive)
    }

    func testMaterialBridgeReadsNoWindowStateAndExposesNoDeadInputs() throws {
        let source = try SourceTestSupport.read("Sources/AppCore/Components/HubMaterial.swift")
        XCTAssertFalse(source.contains("view.window"), "Vibrancy state must have one source: SwiftUI's controlActiveState")
        XCTAssertFalse(source.contains("tint"), "The unused tint input was removed; the system material carries the tone")
        XCTAssertFalse(source.contains("Coordinator"), "A value-only representable needs no coordinator")
    }

    func testWindowChromeConfiguratorHoldsNoGlobalWindowState() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/HubWindowChromeConfigurator.swift")
        XCTAssertFalse(source.contains("static var"), "Per-window glue lives in the Coordinator, never in a process-wide static")
        XCTAssertFalse(source.contains("ObjectIdentifier(window)"))
        XCTAssertTrue(source.contains("final class Coordinator"))
        XCTAssertTrue(source.contains("didClearInitialFocus"))
        XCTAssertTrue(
            source.contains("HubMainWindowIdentity.identifierRawValue"),
            "The NSWindow identifier is the shared constant that focus policy and openWindow also read"
        )
        XCTAssertFalse(source.contains("\"hub.main\""), "No duplicated window identifier literal")
        // The configurator is a window accessor, not a view: one zero-frame NSView, no subclass.
        XCTAssertTrue(source.contains("NSView(frame: .zero)"))
    }

    func testFullScreenStateHoldsNoWindowReference() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubWindowCommandGroup.swift")
        XCTAssertFalse(source.contains("weak var window") || source.contains("var window: NSWindow"))
        XCTAssertTrue(source.contains("NSApp.keyWindow?.styleMask.contains(.fullScreen)"))
        XCTAssertTrue(source.contains("[weak self]"))
    }

    func testAppDelegateServicesAreAssignedOnceAndImmutable() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(source.contains("let registry: ToolRegistry"))
        XCTAssertTrue(source.contains("let router: QuickAccessRouter"))
        XCTAssertTrue(source.contains("let pendingVaultOperationCount: @MainActor () -> Int"))
        XCTAssertFalse(source.contains("static var services"))
    }
}
