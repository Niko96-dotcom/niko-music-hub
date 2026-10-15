import Foundation
import XCTest

/// Warnings fail every build because each target in Package.swift takes
/// `strictSwiftSettings` (-warnings-as-errors). A target added without it would
/// let warnings, and ignored non-discardable results, back in.
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
}
