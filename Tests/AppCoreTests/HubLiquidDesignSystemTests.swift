import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubLiquidDesignSystemTests: XCTestCase {
    func testDeprecatedLiquidGlassAdaptersRemoved() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: "Sources/AppCore/Components/HubLiquidGlass.swift"),
            "HubLiquidGlass.swift should be deleted in v2.0 closure"
        )
        let chrome = try String(
            contentsOfFile: "Sources/AppCore/Components/HubGlassChrome.swift",
            encoding: .utf8
        )
        XCTAssertFalse(chrome.contains("hubGlassChip("))
        XCTAssertFalse(chrome.contains("hubLiquidCard("))
        XCTAssertTrue(chrome.contains("HubShellBackground"))
        XCTAssertTrue(chrome.contains("HubSidebarNavRow"))
    }

    func testSemanticShellPrimitivesHostWithoutCrash() throws {
        XCTAssertNoThrow(try hostView(HubShellBackground(), size: CGSize(width: 240, height: 160)))
        XCTAssertNoThrow(
            try hostView(
                Text("Row").padding().hubSidebarNavRow(isSelected: true),
                size: CGSize(width: 240, height: 80)
            )
        )
    }

    func testFeatureModulesDoNotDeclareLocalLiquidGlassSystem() throws {
        let featureFiles = try swiftFiles(under: "Sources")
            .filter { $0.contains("/Feature") }

        for path in featureFiles {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(source.contains("struct HubLiquid"), "Feature module declares local Liquid primitive: \(path)")
            XCTAssertFalse(source.contains("enum HubLiquid"), "Feature module declares local Liquid namespace: \(path)")
            XCTAssertFalse(source.contains("struct HubGlass"), "Feature module declares local Glass primitive: \(path)")
            XCTAssertFalse(source.contains(".glassEffect("), "Feature module calls glassEffect directly instead of AppCore: \(path)")
        }
    }
}

@MainActor
private func hostView<V: View>(_ view: V, size: CGSize) throws {
    let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = controller.view
    controller.view.layoutSubtreeIfNeeded()
}

private func swiftFiles(under root: String) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: root) else {
        return []
    }

    return enumerator.compactMap { item -> String? in
        guard let item = item as? String, item.hasSuffix(".swift") else {
            return nil
        }
        return "\(root)/\(item)"
    }
}
