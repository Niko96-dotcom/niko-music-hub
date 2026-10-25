import Foundation
import XCTest

/// Where a write may land is decided by two owners: `ToolOutputGuard(settings:)` for tool
/// output and `ArchiveBrowserViewModel.writeProtectedRoots()` for the archive browser's
/// exports and New Song. Writers that chose their own roots shipped five times: the
/// browse list as protection (604025d, e26f73c, fda0cb9) and defaults after an unreadable
/// settings load (e2135e6, 89ff277).
final class OutputGuardSourceTests: XCTestCase {
    func testOnlyToolOutputGuardUsesOutputWriteGuard() throws {
        let failures = try Self.appSourceFiles(excluding: Self.outputWriteGuardOwners).flatMap { file in
            Self.lines(matching: Self.outputWriteGuardUse, in: SourceLex.stripped(try SourceTestSupport.read(file)))
                .map { "\(file):\($0)" }
        }
        XCTAssertEqual(
            failures,
            [],
            "Admit tool output with ToolOutputGuard(settings:).validate(_:) "
                + "(Sources/AppCore/Settings/ToolOutputGuard.swift), not OutputWriteGuard:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// A tool run gets its folder and guard from one `ToolOutputDestination`, so the folder
    /// it writes and the roots it protects come from the same settings read. Before, each
    /// tool paired them its own way, and Stem Separation read settings twice per run.
    func testToolRunsGetTheirGuardFromToolOutputDestination() throws {
        let failures = try Self.appSourceFiles(excluding: Set(Self.toolOutputGuardBuilders.keys)).flatMap { file in
            Self.lines(matching: Self.toolOutputGuardConstruction, in: SourceLex.strippedCommentsOnly(try SourceTestSupport.read(file)))
                .map { "\(file):\($0)" }
        }
        XCTAssertEqual(
            failures,
            [],
            "A tool run admits its output through ToolOutputDestination.load(from:) "
                + "(Sources/AppCore/Settings/ToolOutputDestination.swift), not its own ToolOutputGuard. "
                + "Code that checks a folder outside a run belongs in toolOutputGuardBuilders with its reason:\n"
                + failures.joined(separator: "\n")
        )
        for file in Self.toolOutputGuardBuilders.keys.sorted() {
            let source = SourceLex.strippedCommentsOnly(try SourceTestSupport.read(file))
            XCTAssertFalse(
                Self.lines(matching: Self.toolOutputGuardConstruction, in: source).isEmpty,
                "\(file) no longer builds a ToolOutputGuard. Remove it from toolOutputGuardBuilders."
            )
        }
    }

    func testNoWriterPassesTheBrowseListOrNothingAsProtection() throws {
        let failures = try Self.appSourceFiles(excluding: []).flatMap { file in
            Self.lines(matching: Self.browseListAsProtection, in: SourceLex.stripped(try SourceTestSupport.read(file)))
                .map { "\(file):\($0)" }
        }
        XCTAssertEqual(
            failures,
            [],
            "These pass the browse list (or nothing) as write protection, which leaves Vault roots "
                + "writable while Vault is off. Tools use ToolOutputGuard(settings:); the archive "
                + "browser uses writeProtectedRoots():\n" + failures.joined(separator: "\n")
        )
    }

    /// `try? …loadSettings()` turns unreadable settings into "no settings", and a write
    /// guard built from that protects nothing. Existing sites are counted per file; a file
    /// may lose sites, never gain them.
    func testNoNewTryOptionalSettingsLoads() throws {
        var failures: [String] = []
        var seen: Set<String> = []
        for file in try Self.appSourceFiles(excluding: []) {
            let count = Self.lines(matching: Self.tryOptionalSettingsLoad, in: SourceLex.stripped(try SourceTestSupport.read(file))).count
            let allowed = Self.tryOptionalSettingsLoadBaseline[file] ?? 0
            if count > 0 { seen.insert(file) }
            if count > allowed {
                failures.append("\(file): \(count) `try? …loadSettings()` (baseline \(allowed)). Load with `try` and refuse the action when it throws; display-only code reads ToolContext.appSettings.")
            } else if count < allowed {
                failures.append("\(file): \(count) `try? …loadSettings()`, below its baseline \(allowed). Lower the baseline in OutputGuardSourceTests to \(count).")
            }
        }
        for file in Set(Self.tryOptionalSettingsLoadBaseline.keys).subtracting(seen) {
            failures.append("\(file): no `try? …loadSettings()` left. Remove it from the baseline in OutputGuardSourceTests.")
        }
        XCTAssertEqual(failures.sorted(), [], failures.sorted().joined(separator: "\n"))
    }

    /// The detectors must catch the shipped mistakes, or they guard nothing.
    func testDetectorsCatchTheShippedMistakes() {
        func hits(_ pattern: NSRegularExpression, _ line: String) -> Int {
            Self.lines(matching: pattern, in: SourceLex.stripped(line)).count
        }
        // 604025d^: the converter, downloader and recorder protected the browse list.
        let converter = "try OutputWriteGuard().validateCanWriteOutput(to: settings.outputFolder.url, archiveRoots: settings.archiveRoots.map(\\.url))"
        XCTAssertEqual(hits(Self.outputWriteGuardUse, converter), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, converter), 1)
        // fda0cb9^: exports and New Song protected only the browsed roots.
        XCTAssertEqual(hits(Self.browseListAsProtection, "try policy.enforceNoWrite(at: destination, archiveRoots: roots)"), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, "var created = try NewSongFolderCreator.create(request: request, protectedRoots: roots)"), 1)
        // e2135e6^: the recorder took its destination and roots from defaults on a failed load.
        XCTAssertEqual(hits(Self.tryOptionalSettingsLoad, "let settings = (try? context.settingsStore.loadSettings()) ?? .default"), 1)

        // b5fb166^: the converter built its own guard next to its own folder read.
        func constructions(_ line: String) -> Int {
            Self.lines(matching: Self.toolOutputGuardConstruction, in: SourceLex.strippedCommentsOnly(line)).count
        }
        XCTAssertEqual(constructions("try ToolOutputGuard(settings: settings).validate(settings.outputFolder.url)"), 1)
        XCTAssertEqual(constructions(#"log("refused by \(ToolOutputGuard (settings: settings))")"#), 1, "inside an interpolation")
        XCTAssertEqual(constructions("let destination = try ToolOutputDestination.load(from: context.settingsStore)"), 0)
        XCTAssertEqual(constructions("public let outputGuard: ToolOutputGuard"), 0)
        XCTAssertEqual(constructions("/// only through `ToolOutputGuard(settings:)`."), 0)

        XCTAssertEqual(hits(Self.outputWriteGuardUse, "try ToolOutputGuard(settings: settings).validate(folder)"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "archiveRoots: try writeProtectedRoots(),"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "public init(folder: URL, protectedRoots: [URL]) {"), 0)
        XCTAssertEqual(hits(Self.tryOptionalSettingsLoad, "let settings = try settingsStore.loadSettings()"), 0)
    }

    // MARK: - Detectors

    /// NikoMusicCore implements the policy; ToolOutputGuard is the app's one entry point.
    static let outputWriteGuardOwners: Set<String> = ["Sources/AppCore/Settings/ToolOutputGuard.swift"]

    private static let outputWriteGuardUse = try! NSRegularExpression(pattern: #"\bOutputWriteGuard\b"#)

    /// The files that build a `ToolOutputGuard` themselves, each with its reason. A tool run
    /// never does: it calls `ToolOutputDestination.load(from:)`.
    static let toolOutputGuardBuilders: [String: String] = [
        "Sources/AppCore/Settings/ToolOutputDestination.swift": "the owner: pairs a run's folder with its guard",
        "Sources/NikoMusicHub/Settings/SettingsView.swift": "the output picker checks a candidate folder before it is saved, not a run",
        "Sources/ProjectVaultRuntime/ProjectVaultRecoveryService.swift": "the recovery bundle export writes to a folder the person chose, not the output folder",
    ]

    private static let toolOutputGuardConstruction = try! NSRegularExpression(pattern: #"\bToolOutputGuard\s*\("#)

    private static let browseListAsProtection = try! NSRegularExpression(
        pattern: #"\b(?:archiveRoots|protectedRoots)\s*:\s*(?:try\s+)?(?:self\.)?(?:roots\b|\[\]|[A-Za-z_][\w.]*\.(?:archiveRoots|effectiveScanRoots)\b)"#
    )

    private static let tryOptionalSettingsLoad = try! NSRegularExpression(
        pattern: #"\btry\?\s*[A-Za-z_][\w.?]*\.loadSettings\(\)"#
    )

    /// The `try? …loadSettings()` sites that must stay, each with its reason. Never
    /// add one: load with `try` and refuse the action, or read `ToolContext.appSettings`
    /// for display. Lower a number when a site goes; remove a file at zero.
    static let tryOptionalSettingsLoadBaseline: [String: Int] = [
        // Fails closed: unreadable settings skip launch recovery; the browser's snapshot read reports them.
        "Sources/ProjectVaultRuntime/LiveProjectVaultRuntime+Recovery.swift": 1,
        // The display mirror itself: unreadable settings show defaults; writes load with `try`.
        "Sources/AppCore/Settings/AppSettingsObserver.swift": 1,
        // First-launch probe: a damaged blob belongs to a returning user, who gets no Set Up sheet.
        "Sources/AppCore/Shell/HubFirstLaunchSetupPolicy.swift": 1,
        // Probe: while settings are unreadable the repair notice already explains a Vault read failure.
        "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+ProjectVault.swift": 1,
        // nil keeps the last Vault health and hides cards; the observer lags the model's own saves.
        "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+ProjectVaultPresentation.swift": 1,
        // First-run probe (no new-user sheet for damaged settings), and the access-failure
        // check after a retry, which only presents the next failed root.
        "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Roots.swift": 2,
        // Exclusions only hide folders from a read-only scan; refusing it would hide the library.
        "Sources/FeatureArchiveBrowser/ArchiveCatalogCoordinator.swift": 1,
    ]

    static func lines(matching pattern: NSRegularExpression, in strippedSource: String) -> [String] {
        let ns = strippedSource as NSString
        return pattern.matches(in: strippedSource, range: NSRange(location: 0, length: ns.length)).map { match in
            let line = ns.substring(to: match.range.location).components(separatedBy: "\n").count
            return "\(line): \(ns.substring(with: match.range))"
        }
    }

    /// App sources outside NikoMusicCore (which implements the policy) and the CLI
    /// (whose roots are the archive it was given).
    private static func appSourceFiles(excluding excluded: Set<String>) throws -> [String] {
        let root = SourceTestSupport.packageRoot.standardizedFileURL.path
        let sources = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(root.count + 1)) }
            .filter { !$0.hasPrefix("Sources/NikoMusicCore/") && !$0.hasPrefix("Sources/NikoMusicHubCLI/") }
            .filter { !excluded.contains($0) }
            .sorted()
        XCTAssertGreaterThan(files.count, 100, "Sources/ walk found too few files")
        return files
    }
}
