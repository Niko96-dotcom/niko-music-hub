import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubLiquidDesignSystemTests: XCTestCase {
    func testAppCoreDefinesLiquidPrimitiveNames() throws {
        let appCoreSource = try combinedSource(in: [
            "Sources/AppCore/Components/HubDesignSystem.swift",
            "Sources/AppCore/Components/HubLiquidGlass.swift",
            "Sources/AppCore/Components/HubGlassChrome.swift",
        ])

        [
            "public enum Liquid",
            "public struct HubLiquidBackdrop",
            "public struct HubLiquidPanel",
            "public struct HubLiquidCard",
            "public struct HubGlassField",
            "public struct HubGlassChip",
            "func hubLiquidPanel",
            "func hubLiquidCard",
            "func hubGlassField",
        ].forEach { required in
            XCTAssertTrue(appCoreSource.contains(required), "Missing AppCore Liquid source: \(required)")
        }
    }

    func testLiquidPrimitiveViewsHostWithoutCrash() throws {
        XCTAssertNoThrow(try hostView(HubLiquidBackdrop(), size: CGSize(width: 240, height: 160)))
        XCTAssertNoThrow(try hostView(Text("Panel").padding().hubLiquidPanel(), size: CGSize(width: 240, height: 80)))
        XCTAssertNoThrow(try hostView(Text("Card").padding().hubLiquidCard(intent: .selected), size: CGSize(width: 240, height: 80)))
        XCTAssertNoThrow(try hostView(Text("Field").padding(.horizontal, 8).hubGlassField(), size: CGSize(width: 240, height: 48)))
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

    func testReferenceContractDocumentsMythOSAndExcludesNeuralNote() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("tmp/mythos-reference/contact_sheet.png"))
        XCTAssertTrue(source.contains("output/imagegen/niko-music-hub-liquid-glass-direction.png"))
        XCTAssertTrue(source.contains("MythOS"))
        XCTAssertTrue(source.contains("NeuralNote/laptop"))
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

private func combinedSource(in paths: [String]) throws -> String {
    try paths
        .map { try String(contentsOfFile: $0, encoding: .utf8) }
        .joined(separator: "\n")
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
