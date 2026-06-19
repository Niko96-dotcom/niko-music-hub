import XCTest

final class HubNoNewLiquidCallSitesTests: XCTestCase {
    /// MIG-13 adapter discipline: feature code may not gain NEW HubLiquid*/hubGlass* call
    /// sites after the Phase 51 base commit. This is the count-based baseline (Research
    /// Open Question 4): snapshot the total deprecated-adapter call-site count at Phase 51,
    /// then assert EQUALITY against it.
    ///
    /// Why equality (not `<=`): a `<=` upper bound lets a developer remove one call site
    /// (good) and add another (bad) for a net-zero change that silently passes. Equality
    /// forces *every* delta — increase OR unrecorded decrease — through a deliberate edit
    /// of this constant, so the baseline can never drift out of sync with reality.
    ///
    /// Update protocol:
    ///   - You MIGRATED a call site to semantic tokens (good): decrement
    ///     `baselineCallSiteCount` by the number of adapter call lines you removed.
    ///   - The count went UP: you added a new deprecated-adapter call site. That is a
    ///     MIG-13 violation — remove it or migrate it; do NOT raise the baseline.
    /// The count should only ever DECREASE over the Phase 52–56 migration waves.
    ///
    /// Counting methodology (see WR-02/WR-03): comment lines are stripped first, then each
    /// remaining line is matched against the deprecated adapter *call forms* below
    /// (e.g. `hubLiquidCard(`), one count per matching line. This deliberately excludes
    /// type references such as `HubLiquidSurfaceIntent` (an intent enum used in helper
    /// signatures, not an adapter call site) and prose mentions in doc comments, so the
    /// number tracks real call sites — not substrings.
    private static let baselineCallSiteCount: Int = 65

    /// Deprecated Liquid/Glass adapter call forms feature code may invoke. Matching the
    /// `name(` call form (rather than the bare namespace substring) means a comment or a
    /// type reference cannot inflate the count. Keep this in sync with the deprecated
    /// `func hub{Liquid,Glass}*` View extensions in Sources/AppCore/Components/.
    private static let adapterCallForms: [String] = [
        "hubLiquidCard(",
        "hubLiquidPanel(",
        "hubGlassCard(",
        "hubGlassChip(",
        "hubGlassField(",
        "hubGlassGroup(",
        "hubGlassPanel(",
        "hubGlassChrome(",
    ]

    func testFeatureCodeIntroducesNoNewLiquidGlassCallSites() throws {
        let featureDirs = [
            "Sources/FeatureBPMTapper",
            "Sources/FeatureAudioConverter",
            "Sources/FeatureAudioRecorder",
            "Sources/FeatureDownloader",
            "Sources/FeatureArchiveBrowser",
            "Sources/FeatureStemSeparation",
            "Sources/NikoMusicHub/AppShell",
            "Sources/NikoMusicHub/Settings",
        ]
        var totalCount = 0
        for dir in featureDirs {
            for file in try swiftFiles(under: dir) {
                let source = try String(contentsOfFile: file, encoding: .utf8)
                for line in source.components(separatedBy: .newlines) {
                    // Skip comment lines so prose that mentions a deprecated adapter
                    // (e.g. "migrate the hubLiquidCard() adapter") is not counted.
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                        continue
                    }
                    // One count per matching line (rg -c semantics): a line that invokes
                    // any deprecated adapter call form counts once.
                    if Self.adapterCallForms.contains(where: { line.contains($0) }) {
                        totalCount += 1
                    }
                }
            }
        }
        XCTAssertEqual(
            totalCount,
            Self.baselineCallSiteCount,
            "Liquid/Glass adapter call-site count changed (now \(totalCount), baseline "
                + "\(Self.baselineCallSiteCount)). If you MIGRATED a call site, decrement the "
                + "baseline by the number removed. NEW call sites are forbidden (MIG-13) — "
                + "remove the new call site or migrate it to semantic tokens."
        )
    }

    private func swiftFiles(under root: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { item -> String? in
            guard let item = item as? String, item.hasSuffix(".swift") else { return nil }
            return "\(root)/\(item)"
        }
    }
}
