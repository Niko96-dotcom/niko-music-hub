import Foundation
import XCTest

/// ADR-020: the module rules in AGENTS.md and docs/architecture.md are checked mechanically.
/// Adding a Core framework or a feature→feature edge means changing docs/architecture.md and
/// this test in the same commit, like the design contract.
final class ModuleBoundarySourceTests: XCTestCase {
    /// Core is pure domain code: no SwiftUI, no AppKit, no app modules.
    private static let coreAllowedImports: Set<String> = [
        "Foundation", "Darwin", "SQLite3", "AVFoundation", "CryptoKit", "zlib",
    ]

    /// The one documented feature→feature edge (docs/architecture.md, "Stem Separation → Downloader").
    private static let documentedFeatureEdges: Set<String> = [
        "FeatureStemSeparation -> FeatureDownloader",
    ]

    private static let strictImportCheckFlag = "--explicit-target-dependency-import-check error"

    func testNikoMusicCoreImportsOnlyAllowedFrameworks() throws {
        let files = try swiftFiles(under: "Sources/NikoMusicCore")
        XCTAssertFalse(files.isEmpty, "No Swift sources found under Sources/NikoMusicCore")
        for file in files {
            for module in try importedModules(in: file) where !Self.coreAllowedImports.contains(module) {
                XCTFail("NikoMusicCore imports \(module), which is not in the Core allowlist: \(relativePath(file))")
            }
        }
    }

    func testFeatureModulesImportOnlyDocumentedFeatureEdges() throws {
        let featureModules = try FileManager.default
            .contentsOfDirectory(atPath: SourceTestSupport.packageRoot.appendingPathComponent("Sources").path)
            .filter { $0.hasPrefix("Feature") }
            .sorted()
        XCTAssertGreaterThanOrEqual(featureModules.count, 6, "Feature module directories not found under Sources/")

        var edges: Set<String> = []
        for module in featureModules {
            for file in try swiftFiles(under: "Sources/\(module)") {
                for imported in try importedModules(in: file)
                    where imported != module && featureModules.contains(imported) {
                    edges.insert("\(module) -> \(imported)")
                }
            }
        }
        XCTAssertEqual(
            edges,
            Self.documentedFeatureEdges,
            "Feature→feature imports changed. Document a new edge in docs/architecture.md and update this test in the same commit."
        )
    }

    func testProductBuildsUseStrictTargetImportCheck() throws {
        for script in ["script/ci.sh", "script/lib/app_lifecycle.sh"] {
            let buildCommands = try SourceTestSupport.read(script)
                .components(separatedBy: .newlines)
                // Drop shell comments, so a flag written after `#` does not count.
                .map { $0.replacingOccurrences(of: #"(^|\s)#.*$"#, with: "", options: .regularExpression) }
                // Check every command on a line (`a; b`, `a && b`, `a || b`), wherever it sits
                // (`if ! swift build`, `(cd x && nmh_swift build ...)`).
                .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ";&|")) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("echo ") && !$0.hasPrefix("printf ") }
                .filter { $0.range(of: #"\b(?:nmh_)?swift\s+build\b"#, options: .regularExpression) != nil }
                // --show-bin-path only prints the build directory; it compiles nothing.
                .filter { !$0.contains("--show-bin-path") }
            XCTAssertFalse(buildCommands.isEmpty, "No swift build command found in \(script)")
            for command in buildCommands {
                XCTAssertTrue(
                    command.contains(Self.strictImportCheckFlag),
                    "\(script) builds without \(Self.strictImportCheckFlag): \(command)"
                )
            }
        }
    }

    // MARK: - Helpers

    /// Top-level module names of every `import` statement in the file, including attributed
    /// (`@preconcurrency import X`), access-level (`public import X`), kind (`import struct X.Y`),
    /// submodule (`import X.Y`) and `;`-separated forms.
    private func importedModules(in path: String) throws -> [String] {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let pattern = #"(?:^|;)[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)"#
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private func swiftFiles(under relativeRoot: String) throws -> [String] {
        let root = SourceTestSupport.packageRoot.appendingPathComponent(relativeRoot).path
        guard let enumerator = FileManager.default.enumerator(atPath: root) else {
            XCTFail("Missing source directory: \(relativeRoot)")
            return []
        }
        return enumerator.compactMap { item -> String? in
            guard let item = item as? String, item.hasSuffix(".swift") else { return nil }
            return "\(root)/\(item)"
        }
    }

    private func relativePath(_ path: String) -> String {
        path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
    }
}
