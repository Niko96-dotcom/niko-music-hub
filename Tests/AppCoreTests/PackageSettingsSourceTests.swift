import Foundation
import XCTest

/// Warnings fail every build because each target in Package.swift takes
/// `strictSwiftSettings` (-warnings-as-errors). A target added without it would
/// let warnings, and ignored non-discardable results, back in. The warnings the
/// flag cannot promote fail ./script/ci.sh instead.
final class PackageSettingsSourceTests: XCTestCase {
    func testEveryTargetBuildsWithWarningsAsErrors() throws {
        let manifest = SourceLex.strippedCommentsOnly(try SourceTestSupport.read("Package.swift"))
        XCTAssertTrue(
            manifest.contains(#".unsafeFlags(["-warnings-as-errors"])"#),
            "Package.swift no longer defines strictSwiftSettings with -warnings-as-errors"
        )
        let declarations = try NSRegularExpression(pattern: #"\.(?:target|executableTarget|testTarget)\(\s*name:\s*"([^"]+)""#)
        let ns = manifest as NSString
        let matches = declarations.matches(in: manifest, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThanOrEqual(matches.count, 20, "Package.swift target walk found too few targets")
        for (index, match) in matches.enumerated() {
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let declaration = ns.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
            XCTAssertTrue(
                declaration.contains("swiftSettings: strictSwiftSettings"),
                "Target \(ns.substring(with: match.range(at: 1))) in Package.swift has no `swiftSettings: strictSwiftSettings`"
            )
        }
    }

    /// -warnings-as-errors cannot promote a warning Swift downgraded itself: a call into
    /// main-actor isolation inferred from a @preconcurrency protocol (SwiftUI's `View`) stays
    /// a warning. ./script/ci.sh catches those with a build into an empty scratch path, the
    /// only build that prints every file's warnings, and fails on any warning in its log but
    /// SwiftPM's notices about a pinned dependency (a package-cache race, not this code).
    func testCIFailsOnAnyWarningInACleanBuild() throws {
        let script = try SourceTestSupport.read("script/ci.sh")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"(^|\s)#.*$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
        for fragment in [
            #"CLEAN_BUILD="$(mktemp -d"#,
            #"swift build --build-tests --explicit-target-dependency-import-check error --scratch-path "$CLEAN_BUILD" 2>&1 | tee "$CLEAN_BUILD_LOG""#,
            #"BUILD_WARNINGS="$(sed $'s/\033\\[[0-9;]*m//g' "$CLEAN_BUILD_LOG" | grep 'warning: ' | grep -Ev "$DEPENDENCY_NOTICE" || true)""#,
            #"if [[ -n "$BUILD_WARNINGS" ]]; then"#,
        ] {
            XCTAssertTrue(script.contains(fragment), "script/ci.sh no longer fails on warnings of a clean build: missing `\(fragment)`")
        }
    }
}
