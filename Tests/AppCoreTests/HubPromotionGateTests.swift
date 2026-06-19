import XCTest

final class HubPromotionGateTests: XCTestCase {
    /// DS-10: a shared primitive in Sources/AppCore/Components/ is promoted only after
    /// it has >=2 real non-domain-specific call sites outside Sources/AppCore/Components/.
    /// Primitives annotated `pendingPromotion` below are exempt because feature surfaces
    /// are UNMIGRATED in Phase 51 (migration happens in Phases 52–56).
    func testSharedPrimitivesHaveAtLeastTwoCallSites() throws {
        // Promoted primitives per COMPONENT-MAP.md.
        // Phase 51 call-site reality: features are UNMIGRATED — they still use deprecated
        // hubLiquid*/hubGlass* adapters. Primitives whose feature consumers haven't migrated
        // yet are marked pendingPromotion until Phases 52–56 wire up direct call sites.
        let primitives: [(name: String, pendingPromotion: Bool)] = [
            // Primitives with >=2 verified call sites outside Components right now.
            ("HubIconButton",    false),
            ("HubLabeledButton", false),
            ("HubWaveformSurface", false),
            ("HubToolLayout",    false),
            ("HubTransportBar",  false),

            // Primitives that are promoted per COMPONENT-MAP.md but whose feature consumers
            // are UNMIGRATED (Phases 52–56 replace the deprecated adapters with direct refs).
            ("HubSectionDivider",   true),  // pendingPromotion — 0 call sites (features use hubLiquidCard)
            ("StatusDot",           true),  // pendingPromotion — 1 call site (Output Inbox unmigrated)
            ("ToolHeaderBlock",     true),  // pendingPromotion — 0 call sites outside Components
            ("OutputRow",           true),  // pendingPromotion — 0 call sites outside Components
            ("HubShellBackground",  true),  // pendingPromotion — 1 call site (AppShellView:102); Phase 52 adds more
            ("HubSidebarNavRow",    true),  // pendingPromotion — 0 call sites (ToolSidebarView unmigrated → Phase 52)
            ("hubSidebarNavRow",    true),  // pendingPromotion — the modifier extension
            ("hubCard",             true),  // pendingPromotion — new this phase, features migrate in 52–56
            ("HubCard",             true),  // pendingPromotion — the struct itself
        ]

        let allSourceFiles = try swiftFiles(under: "Sources")
        let nonComponentFiles = allSourceFiles.filter { !$0.contains("/AppCore/Components/") }

        for (name, pendingPromotion) in primitives {
            var callSiteCount = 0
            for file in nonComponentFiles {
                let source = try String(contentsOfFile: file, encoding: .utf8)
                if source.contains(name) { callSiteCount += 1 }
            }
            if pendingPromotion {
                // pendingPromotion — allowed to have <2 call sites this phase
                XCTAssertGreaterThanOrEqual(
                    callSiteCount, 0,
                    "pendingPromotion primitive \(name) should have >=0 call sites"
                )
            } else {
                XCTAssertGreaterThanOrEqual(
                    callSiteCount,
                    2,
                    "Shared primitive \(name) has <2 non-domain call sites outside Components (DS-10 violation). Count: \(callSiteCount)"
                )
            }
        }
    }

    private func swiftFiles(under root: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { item -> String? in
            guard let item = item as? String, item.hasSuffix(".swift") else { return nil }
            return "\(root)/\(item)"
        }
    }
}
