import Foundation
import XCTest

/// Warnings fail every build because each target in Package.swift takes `strictSwiftSettings`
/// (-warnings-as-errors). A target added without it would let warnings, and ignored non-discardable
/// results, back in. The warnings the flag cannot promote fail ./script/ci.sh instead.
/// AGENTS.md row "No warnings"; CONTRIBUTING.md § Gates.
final class PackageSettingsSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "No warnings",
        why: "Clean-build warnings were cleared by hand twice and came back; an ignored refusal is only a warning otherwise",
        see: "AGENTS.md row \"No warnings\"; CONTRIBUTING.md § Gates",
        fix: "Give the target `swiftSettings: strictSwiftSettings`, and keep ci.sh's clean build and warning check"
    )

    func testEveryTargetBuildsWithWarningsAsErrors() {
        let manifest = SourceLex.strippedCommentsOnly(SourceTree.read("Package.swift"))
        Self.rule.require(
            manifest.contains(#".unsafeFlags(["-warnings-as-errors"])"#),
            "Package.swift no longer defines strictSwiftSettings with -warnings-as-errors"
        )
        let declarations = SourceTree.matches(SourceTree.regex(#"\.(?:target|executableTarget|testTarget)\(\s*name:\s*"([^"]+)""#), in: manifest)
        XCTAssertGreaterThanOrEqual(declarations.count, 20, "Package.swift target walk found too few targets")
        let ns = manifest as NSString
        let starts = declarations.map { ns.range(of: $0.text).location }
        for (index, declaration) in declarations.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : ns.length
            let body = ns.substring(with: NSRange(location: starts[index], length: end - starts[index]))
            Self.rule.require(
                body.contains("swiftSettings: strictSwiftSettings"),
                "Package.swift:\(declaration.line) declares \(declaration.text) without `swiftSettings: strictSwiftSettings`"
            )
        }
    }

    /// -warnings-as-errors cannot promote a warning Swift downgraded itself: a call into
    /// main-actor isolation inferred from a @preconcurrency protocol (SwiftUI's `View`) stays
    /// a warning. ./script/ci.sh catches those with a build into an empty scratch path, the
    /// only build that prints every file's warnings, and fails on any warning in its log but
    /// SwiftPM's notices about a pinned dependency (a package-cache race, not this code).
    func testCIFailsOnAnyWarningInACleanBuild() {
        let script = SourceTree.read("script/ci.sh")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"(^|\s)#.*$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
        for fragment in [
            #"CLEAN_BUILD="$(mktemp -d"#,
            #"swift build --build-tests --explicit-target-dependency-import-check error --scratch-path "$CLEAN_BUILD" 2>&1 | tee "$CLEAN_BUILD_LOG""#,
            #"DEPENDENCY_NOTICE="^warning: '($(sed -n 's/.*"identity" : "\([^"]*\)".*/\1/p' Package.resolved | paste -sd'|' -))': ""#,
            #"BUILD_WARNINGS="$(sed $'s/\033\\[[0-9;]*m//g' "$CLEAN_BUILD_LOG" | grep 'warning: ' | grep -Ev "$DEPENDENCY_NOTICE" || true)""#,
            #"if [[ -n "$BUILD_WARNINGS" ]]; then"#,
        ] {
            Self.rule.require(script.contains(fragment), "script/ci.sh no longer fails on warnings of a clean build: missing `\(fragment)`")
        }
    }
}
