import Foundation
import XCTest

/// The person's real defaults are picked in one place: `AppComposition.makeUserDefaults`
/// (plus the App's AppKit `register(defaults:)`). Everything else takes a `UserDefaults`
/// or `PreferenceStore` it is given. Tests and harnesses that reached
/// `UserDefaults.standard` wrote into the real app's preferences (c125e75, 9e5837d), and
/// the store initializers no longer default to `.standard`.
final class RealUserDefaultsSourceTests: XCTestCase {
    static let owners: Set<String> = [
        "Sources/NikoMusicHub/AppComposition.swift",
        "Sources/NikoMusicHub/NikoMusicHubApp.swift",
    ]

    func testOnlyTheCompositionRootReadsRealUserDefaults() throws {
        var failures: [String] = []
        for file in try Self.swiftFiles(under: ["Sources", "Tests"]) where !Self.owners.contains(file) {
            let source = SourceLex.stripped(try SourceTestSupport.read(file))
            failures += Self.violations(in: source).map { "\(file):\($0)" }
        }
        XCTAssertEqual(
            failures,
            [],
            "These lines reach the person's real defaults. Take a UserDefaults or PreferenceStore "
                + "parameter instead; tests use InMemoryPreferenceStore or UserDefaults(suiteName:). "
                + "Only AppComposition.makeUserDefaults picks real defaults:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// The detector must catch the shipped mistakes, or it guards nothing.
    func testDetectorCatchesTheShippedMistakes() {
        let shipped = [
            // c125e75^: DownloaderViewModelTests seeded and restored the real key.
            #"UserDefaults.standard.set(try JSONEncoder().encode(selection), forKey: "downloader.formatSelection")"#,
            "let originalStandard = UserDefaults.standard.data(forKey: key)",
            // The store initializers before this guard.
            "public init(userDefaults: UserDefaults = .standard) {",
        ]
        for line in shipped {
            XCTAssertFalse(Self.violations(in: SourceLex.stripped(line)).isEmpty, "Detector misses: \(line)")
        }
        let allowed = [
            "let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))",
            "UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)",
            "locator: HelperToolLocator = .standard()",
        ]
        for line in allowed {
            XCTAssertEqual(Self.violations(in: SourceLex.stripped(line)), [], "Detector flags allowed code: \(line)")
        }
    }

    // MARK: - Detector

    private static let realDefaults = try! NSRegularExpression(
        pattern: #"\bUserDefaults\s*\.\s*standard\b|\bUserDefaults\s*=\s*\.standard\b"#
    )

    static func violations(in strippedSource: String) -> [String] {
        let ns = strippedSource as NSString
        return realDefaults.matches(in: strippedSource, range: NSRange(location: 0, length: ns.length)).map { match in
            let line = ns.substring(to: match.range.location).components(separatedBy: "\n").count
            return "\(line): \(ns.substring(with: match.range))"
        }
    }

    private static func swiftFiles(under directories: [String]) throws -> [String] {
        let root = SourceTestSupport.packageRoot.standardizedFileURL.path
        var files: [String] = []
        for directory in directories {
            let url = SourceTestSupport.packageRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            files += enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
                .map { String($0.standardizedFileURL.path.dropFirst(root.count + 1)) }
        }
        XCTAssertGreaterThan(files.count, 300, "Sources/ and Tests/ walk found too few files")
        return files.sorted()
    }
}
