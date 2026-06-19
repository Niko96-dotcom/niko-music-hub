import XCTest

final class HubNoNewLiquidCallSitesTests: XCTestCase {
    /// MIG-13 adapter discipline: feature code may not gain NEW HubLiquid*/hubGlass* call sites
    /// after the Phase 51 base commit. This is the count-based baseline (Research Open Question 4):
    /// snapshot the total Liquid/Glass call-site count at Phase 51 commit; fail if it increases.
    /// Update this constant only when a controlled Phase 52–56 migration wave removes call sites
    /// (the count should DECREASE over time, never increase).
    private static let baselineCallSiteCount: Int = 70

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
                // Count lines (matches rg -c semantics: one count per matching line)
                let lines = source.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("HubLiquid") || line.contains("hubLiquid")
                        || line.contains("HubGlass") || line.contains("hubGlass")
                    {
                        totalCount += 1
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(
            totalCount,
            Self.baselineCallSiteCount,
            "Feature code gained NEW HubLiquid*/hubGlass* call sites (MIG-13 violation). "
                + "Baseline: \(Self.baselineCallSiteCount), actual: \(totalCount). "
                + "Remove the new call site or migrate it to semantic tokens."
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
