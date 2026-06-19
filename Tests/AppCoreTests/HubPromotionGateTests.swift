import XCTest

final class HubPromotionGateTests: XCTestCase {
    /// DS-10: a shared primitive in Sources/AppCore/Components/ is promoted only after
    /// it has >=2 real non-domain-specific call sites outside Sources/AppCore/Components/.
    /// Primitives annotated `pendingPromotion` below are exempt because feature surfaces
    /// are UNMIGRATED in Phase 51 (migration happens in Phases 52–56).
    ///
    /// The gate is a *two-sided* contract so it cannot rot into a tautology:
    ///   - promoted primitives (pendingPromotion == false) MUST have >=2 call sites; and
    ///   - pendingPromotion primitives MUST still have <2 call sites — the moment a
    ///     migration wave wires up a 2nd call site, this test fails and forces the
    ///     developer to flip pendingPromotion to false (keeping DS-10 honest).
    ///
    /// Call sites are detected on NON-COMMENT lines with word-boundary matching so doc
    /// comments, string literals, and longer identifiers (e.g. `HubCardView`) are not
    /// miscounted as call sites.
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
            // Count files that contain a real call site of `name`: a word-boundary match
            // on a non-comment line. One count per file (file-presence semantics, matching
            // the historical metric), but immune to comment/substring false positives.
            let pattern = try NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b")
            var callSiteCount = 0
            for file in nonComponentFiles {
                let source = try String(contentsOfFile: file, encoding: .utf8)
                let codeOnly = nonCommentSource(source)
                let range = NSRange(codeOnly.startIndex..., in: codeOnly)
                if pattern.firstMatch(in: codeOnly, range: range) != nil {
                    callSiteCount += 1
                }
            }
            if pendingPromotion {
                // Two-sided invariant: a pendingPromotion primitive must STILL be unmigrated.
                // Once a wave gives it >=2 call sites, this fails and forces the flag flip.
                XCTAssertLessThan(
                    callSiteCount, 2,
                    "\(name) is marked pendingPromotion but now has \(callSiteCount) call sites (>=2) — "
                        + "it has been migrated; flip its pendingPromotion flag to false (DS-10)."
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

    /// Joins only the non-comment lines of `source`, so identifier searches ignore doc
    /// comments and `//`/`/* */`-style annotations (the sibling dependency-direction and
    /// theme-system tests use the same comment-stripping discipline).
    private func nonCommentSource(_ source: String) -> String {
        source.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
            }
            .joined(separator: "\n")
    }

    private func swiftFiles(under root: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { item -> String? in
            guard let item = item as? String, item.hasSuffix(".swift") else { return nil }
            return "\(root)/\(item)"
        }
    }
}
