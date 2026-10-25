import XCTest

/// The module rules are checked mechanically (ADR 020). Adding a Core framework, a feature→feature
/// edge or a Project Vault runtime edge (ADR 022) means changing docs/architecture.md and this test in
/// the same commit, like the design contract. The strict import check refuses an import that
/// Package.swift does not declare; this test pins which edges Package.swift may declare.
/// AGENTS.md row "Module boundaries"; docs/decisions/020-module-boundary-checks.md, 022.
final class ModuleBoundarySourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Module boundaries",
        why: "Core stays pure, features stay independent, and the Vault runtime has one consumer; an unplanned edge ties modules together",
        see: "AGENTS.md row \"Module boundaries\"; docs/decisions/020-module-boundary-checks.md; docs/decisions/022-appcore-scope-and-vault-runtime-target.md",
        fix: "Remove the import, or document the new edge in docs/architecture.md and this test in the same commit"
    )

    /// Core is pure domain code: no SwiftUI, no AppKit, no app modules.
    private static let coreAllowedImports: Set<String> = ["Foundation", "Darwin", "SQLite3", "AVFoundation", "CryptoKit", "zlib"]

    /// The one documented feature→feature edge (docs/architecture.md, "Stem Separation → Downloader").
    private static let documentedFeatureEdges: Set<String> = ["FeatureStemSeparation -> FeatureDownloader"]

    /// ADR-022: the Project Vault runtime sits on the shell kit and Core, with no UI frameworks.
    private static let vaultRuntimeAllowedImports: Set<String> = ["AppCore", "NikoMusicCore", "Foundation", "Darwin", "CryptoKit"]

    /// ADR-022: the archive feature and the app target use the Vault runtime; the shell kit and every
    /// other module do not.
    private static let vaultRuntimeImporters: Set<String> = ["FeatureArchiveBrowser", "NikoMusicHub"]

    private static let strictImportCheckFlag = "--explicit-target-dependency-import-check error"

    func testNikoMusicCoreImportsOnlyAllowedFrameworks() {
        Self.rule.check(Self.imports(in: "NikoMusicCore").filter { !Self.coreAllowedImports.contains($0.module) }.map {
            "\($0.path) imports \($0.module), which is not in the Core allowlist"
        })
    }

    func testFeatureModulesImportOnlyDocumentedFeatureEdges() {
        let features = SourceTree.modules.filter { $0.hasPrefix("Feature") }
        XCTAssertGreaterThanOrEqual(features.count, 6, "Feature module directories not found under Sources/")
        let edges = Set(features.flatMap { module in
            Self.imports(in: module).filter { $0.module != module && features.contains($0.module) }.map { "\(module) -> \($0.module)" }
        })
        Self.rule.check(edges.subtracting(Self.documentedFeatureEdges).sorted().map { "Feature edge \($0) is not documented" })
        Self.rule.check(Self.documentedFeatureEdges.subtracting(edges).sorted().map { "Documented feature edge \($0) is gone; update the docs and this test" })
    }

    func testProjectVaultRuntimeImportsOnlyShellKitCoreAndSystemFrameworks() {
        Self.rule.check(Self.imports(in: "ProjectVaultRuntime").filter { !Self.vaultRuntimeAllowedImports.contains($0.module) }.map {
            "\($0.path) imports \($0.module), which is not in the Vault runtime's allowlist"
        })
    }

    func testOnlyTheArchiveFeatureAndTheAppImportProjectVaultRuntime() {
        let modules = SourceTree.modules.filter { $0 != "ProjectVaultRuntime" }
        XCTAssertTrue(modules.contains("AppCore"), "Source module directories not found under Sources/")
        let importers = Set(modules.filter { module in Self.imports(in: module).contains { $0.module == "ProjectVaultRuntime" } })
        Self.rule.require(importers == Self.vaultRuntimeImporters,
                          "ProjectVaultRuntime is imported by \(importers.sorted()); ADR 022 allows only \(Self.vaultRuntimeImporters.sorted())")
    }

    func testProductBuildsUseStrictTargetImportCheck() {
        for script in ["script/ci.sh", "script/ci-release.sh", "script/lib/app_lifecycle.sh"] {
            let buildCommands = SourceTree.read(script)
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
            Self.rule.require(!buildCommands.isEmpty, "No swift build command found in \(script)")
            Self.rule.check(buildCommands.filter { !$0.contains(Self.strictImportCheckFlag) }.map {
                "\(script) builds without \(Self.strictImportCheckFlag): \($0)"
            })
        }
    }

    /// Top-level module names of every `import` statement in a module's files, including attributed
    /// (`@preconcurrency import X`), access-level (`public import X`), kind (`import struct X.Y`),
    /// submodule (`import X.Y`) and `;`-separated forms.
    private static func imports(in module: String) -> [(path: String, module: String)] {
        let files = SourceTree.swiftFiles(under: "Sources/\(module)/")
        let statement = SourceTree.regex(
            #"(?:^|;)[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)"#,
            options: .anchorsMatchLines
        )
        return files.flatMap { path -> [(path: String, module: String)] in
            let source = SourceTree.read(path) as NSString
            return statement.matches(in: source as String, range: NSRange(location: 0, length: source.length)).map {
                (path, source.substring(with: $0.range(at: 1)))
            }
        }
    }
}
