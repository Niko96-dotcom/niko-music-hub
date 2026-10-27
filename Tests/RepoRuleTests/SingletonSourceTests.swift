import XCTest

/// Collaborators come in through an initializer, `ToolContext` or a host struct, built in
/// `AppComposition.make()`. A `static let shared` hides the dependency from the initializer and hands every
/// caller, a test included, the one live instance: `LiveProcessGroupRegistry.shared` (removed in e608079) and
/// `HubHelpRouting.shared` shipped that way.
/// AGENTS.md row "No singletons"; docs/architecture-map.md gap 5.
final class SingletonSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "No singletons",
        why: "A shared instance hides a dependency from the initializer and hands every caller the one live object",
        see: "AGENTS.md row \"No singletons\"; docs/architecture-map.md gap 5",
        fix: "Build the instance in AppComposition.make() and pass it in through an initializer, ToolContext or a host struct"
    )

    /// Each singleton that may stay, with its reason.
    static let allowed: [String: String] = [
        "Sources/NikoMusicCore/Support/ConfidenceReasonPool.swift":
            "an interning cache: a caller gets an equal array with or without it, so no behavior depends on it",
    ]

    func testNoSharedSingletonsUnderSources() {
        let found = SourceTree.matches(Self.pattern, in: SourceTree.swiftFiles(under: "Sources/", atLeast: 300))
        Self.rule.check(found.filter { Self.allowed[$0.path] == nil }, "declares a shared singleton")
        for path in Self.allowed.keys.sorted() where !found.contains(where: { $0.path == path }) {
            Self.rule.check(["\(path) no longer declares a singleton; remove it from the allowed list"])
        }
    }

    /// The detector must catch the shipped mistakes, or it guards nothing.
    func testDetectorCatchesTheShippedMistakes() {
        let regex = SourceTree.regex(Self.pattern)
        let shipped = [
            "public static let shared = LiveProcessGroupRegistry()",
            "    static let shared = HubHelpRouting()",
            "nonisolated(unsafe) static var shared = Cache()",
        ]
        for line in shipped {
            XCTAssertFalse(SourceTree.matches(regex, in: SourceLex.stripped(line)).isEmpty, "Detector misses: \(line)")
        }
        let allowed = [
            "NSWorkspace.shared.open(url)",
            "if let shared = canonicalByReasons[reasons] { return shared }",
            "static let sharedDefaults = makeDefaults()",
        ]
        for line in allowed {
            XCTAssertEqual(SourceTree.matches(regex, in: SourceLex.stripped(line)), [], "Detector flags allowed code: \(line)")
        }
    }

    private static let pattern = #"\bstatic\s+(?:let|var)\s+shared\b"#
}
