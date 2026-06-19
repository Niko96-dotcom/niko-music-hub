import XCTest

final class HubDependencyDirectionTests: XCTestCase {
    /// DS-04: Sources/AppCore/Components/ imports no feature module and contains no
    /// feature/domain model type names (Song, Job, OutputInboxItem, StemOutput).
    func testAppCoreComponentsImportNoFeatureModule() throws {
        let componentFiles = try swiftFiles(under: "Sources/AppCore/Components")
        let forbiddenImports = [
            "import FeatureArchiveBrowser",
            "import FeatureBPMTapper",
            "import FeatureAudioConverter",
            "import FeatureAudioRecorder",
            "import FeatureDownloader",
            "import FeatureStemSeparation",
            "import NikoMusicCore",
        ]
        for path in componentFiles {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            for forbidden in forbiddenImports {
                XCTAssertFalse(
                    source.contains(forbidden),
                    "AppCore Components file imports a feature/domain module (DS-04 violation): \(path) — \(forbidden)"
                )
            }
        }
    }

    func testAppCoreComponentsContainNoDomainModelTypeNames() throws {
        let componentFiles = try swiftFiles(under: "Sources/AppCore/Components")
        let forbiddenTypeNames = ["Song", "Job", "OutputInboxItem", "StemOutput"]
        for path in componentFiles {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            for forbidden in forbiddenTypeNames {
                // Word-boundary check to avoid false positives (e.g. "Song" inside "Songbird")
                let regex = try NSRegularExpression(pattern: "\\b\(forbidden)\\b")
                let matches = regex.matches(
                    in: source,
                    range: NSRange(source.startIndex..., in: source)
                )
                XCTAssertTrue(
                    matches.isEmpty,
                    "AppCore Components file references a domain model type (DS-04 violation): \(path) — \(forbidden)"
                )
            }
        }
    }

    /// DS-01/DS-09: no second theme/V2 system and no mutable global ThemeManager exists.
    /// Non-comment lines only — doc comments that mention "ThemeManager" as a concept
    /// (e.g. "no mutable global ThemeManager") are not violations.
    func testNoSecondThemeSystemOrThemeManagerExists() throws {
        let allSources = try swiftFiles(under: "Sources")
        let forbiddenSymbols = [
            "ThemeV2", "LiquidV2", "CalmCard", "UniversalCard", "UniversalPanel", "ThemeManager",
        ]
        for path in allSources {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            // Strip comment lines before searching — doc comments may mention forbidden
            // symbols as concepts (e.g. "no mutable global ThemeManager"); those are not violations.
            let nonCommentLines = source.components(separatedBy: .newlines)
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
                }
            let nonCommentSource = nonCommentLines.joined(separator: "\n")
            for forbidden in forbiddenSymbols {
                XCTAssertFalse(
                    nonCommentSource.contains(forbidden),
                    "A second theme/V2 system or ThemeManager exists in non-comment code (DS-01/DS-09 violation): \(path) — \(forbidden)"
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
