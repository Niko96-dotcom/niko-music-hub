import XCTest

/// The person's real defaults are picked in one place: `AppComposition.makeUserDefaults` (plus the
/// App's AppKit `register(defaults:)`). Everything else takes a `UserDefaults` or `PreferenceStore` it is
/// given. Tests and harnesses that reached `UserDefaults.standard` wrote into the real app's preferences
/// (c125e75, 9e5837d), and the store initializers no longer default to `.standard`.
/// AGENTS.md row "Real defaults"; docs/architecture-map.md § State owners.
final class RealUserDefaultsSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Real defaults",
        why: "Tests and harnesses that reached UserDefaults.standard wrote into the person's real app preferences",
        see: "AGENTS.md row \"Real defaults\"; docs/architecture-map.md § State owners",
        fix: "Take a UserDefaults or PreferenceStore parameter; tests use InMemoryPreferenceStore or UserDefaults(suiteName:)"
    )

    static let owners: Set<String> = [
        "Sources/NikoMusicHub/AppComposition.swift",
        "Sources/NikoMusicHub/NikoMusicHubApp.swift",
    ]

    func testOnlyTheCompositionRootReadsRealUserDefaults() {
        let files = SourceTree.swiftFiles(under: "", atLeast: 300).filter { !Self.owners.contains($0) }
        Self.rule.check(files.flatMap { Self.violations(in: SourceTree.read($0, .code), path: $0) }, "reaches the person's real defaults")
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

    private static let realDefaults = SourceTree.regex(#"\bUserDefaults\s*\.\s*standard\b|\bUserDefaults\s*=\s*\.standard\b"#)

    static func violations(in strippedSource: String, path: String = "") -> [SourceTree.Match] {
        SourceTree.matches(realDefaults, in: strippedSource, path: path)
    }
}
