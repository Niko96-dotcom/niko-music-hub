import XCTest

/// Where a write may land is decided by two owners: `ToolOutputGuard(settings:)` for tool output and
/// `ArchiveLibraryModel.writeProtectedRoots()` for the archive browser's exports and New Song. Writers
/// that chose their own roots shipped five times: the browse list as protection (604025d, e26f73c,
/// fda0cb9) and defaults after an unreadable settings load (e2135e6, 89ff277).
/// AGENTS.md rows "Output admission" and "Settings for a write"; docs/architecture.md § Safety architecture.
final class OutputGuardSourceTests: XCTestCase {
    static let admission = RepoRule(
        name: "Output admission",
        why: "Writers that picked their own protected roots left Vault roots writable while Vault was off; it shipped five times",
        see: "AGENTS.md row \"Output admission\"; docs/architecture.md § Safety architecture, § Tool output destination",
        fix: "A tool run calls ToolOutputDestination.load(from:); other checks use ToolOutputGuard(settings:); the archive uses writeProtectedRoots()"
    )
    static let settingsForWrite = RepoRule(
        name: "Settings for a write",
        why: "`try? …loadSettings()` turns unreadable settings into defaults, and a guard built from them protects nothing",
        see: "AGENTS.md row \"Settings for a write\"; docs/architecture.md § Safety architecture",
        fix: "Load with `try` and refuse the action when it throws; display-only code reads ToolContext.appSettings"
    )

    /// NikoMusicCore implements the policy; ToolOutputGuard is the app's one entry point.
    static let outputWriteGuardOwners: Set<String> = ["Sources/AppCore/Settings/ToolOutputGuard.swift"]

    /// The files that build a `ToolOutputGuard` themselves, each with its reason. A tool run never does:
    /// it calls `ToolOutputDestination.load(from:)`.
    static let toolOutputGuardBuilders: [String: String] = [
        "Sources/AppCore/Settings/ToolOutputDestination.swift": "the owner: pairs a run's folder with its guard",
        "Sources/NikoMusicHub/Settings/SettingsView.swift": "the output picker checks a candidate folder before it is saved, not a run",
        "Sources/ProjectVaultRuntime/ProjectVaultRecoveryService.swift": "the recovery bundle export writes to a folder the person chose, not the output folder",
    ]

    /// The `try? …loadSettings()` sites that must stay, each with its reason. Never add one: load with
    /// `try` and refuse the action, or read `ToolContext.appSettings` for display. Lower a number when a
    /// site goes; remove a file at zero.
    static let tryOptionalSettingsLoadBaseline: [String: Int] = [
        // Fails closed: unreadable settings skip launch recovery; the browser's snapshot read reports them.
        "Sources/ProjectVaultRuntime/LiveProjectVaultRuntime+Recovery.swift": 1,
        // The display mirror itself: unreadable settings show defaults; writes load with `try`.
        "Sources/AppCore/Settings/AppSettingsObserver.swift": 1,
        // First-launch probe: a damaged blob belongs to a returning user, who gets no Set Up sheet.
        "Sources/AppCore/Shell/HubFirstLaunchSetupPolicy.swift": 1,
        // Probe: while settings are unreadable the repair notice already explains a Vault read failure;
        // and the card context: nil keeps the last Vault health and hides cards, the observer lags the
        // model's own saves.
        "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+ProjectVault.swift": 2,
        // First-run probe (no new-user sheet for damaged settings), and the access-failure
        // check after a retry, which only presents the next failed root.
        "Sources/FeatureArchiveBrowser/ArchiveLibraryModel.swift": 2,
        // Exclusions only hide folders from a read-only scan; refusing it would hide the library.
        "Sources/FeatureArchiveBrowser/ArchiveCatalogCoordinator.swift": 1,
    ]

    static let outputWriteGuardUse = #"\bOutputWriteGuard\b"#
    static let toolOutputGuardConstruction = #"\bToolOutputGuard\s*\("#
    static let browseListAsProtection =
        #"\b(?:archiveRoots|protectedRoots)\s*:\s*(?:try\s+)?(?:(?:[A-Za-z_][\w.]*\.)?roots\b(?:\(\))?|\[\]|[A-Za-z_][\w.]*\.(?:archiveRoots|effectiveScanRoots)\b)"#
    static let tryOptionalSettingsLoad = #"\btry\?\s*[A-Za-z_][\w.?]*\.loadSettings\(\)"#

    /// App sources outside NikoMusicCore (which implements the policy) and the CLI (whose roots are the
    /// archive it was given).
    private static var appSourceFiles: [String] {
        SourceTree.swiftFiles(under: "Sources/", atLeast: 100)
            .filter { !$0.hasPrefix("Sources/NikoMusicCore/") && !$0.hasPrefix("Sources/NikoMusicHubCLI/") }
    }

    func testOnlyToolOutputGuardUsesOutputWriteGuard() {
        let files = Self.appSourceFiles.filter { !Self.outputWriteGuardOwners.contains($0) }
        Self.admission.check(SourceTree.matches(Self.outputWriteGuardUse, in: files), "uses OutputWriteGuard; admit tool output with ToolOutputGuard(settings:)")
    }

    /// A tool run gets its folder and guard from one `ToolOutputDestination`, so the folder it writes and
    /// the roots it protects come from the same settings read. Before, each tool paired them its own way,
    /// and Stem Separation read settings twice per run.
    func testToolRunsGetTheirGuardFromToolOutputDestination() {
        let builds = SourceTree.matches(Self.toolOutputGuardConstruction, in: Self.appSourceFiles, .codeAndStrings)
        Self.admission.check(builds.filter { Self.toolOutputGuardBuilders[$0.path] == nil },
                             "builds its own ToolOutputGuard; a check outside a run belongs in toolOutputGuardBuilders with its reason")
        for file in Self.toolOutputGuardBuilders.keys.sorted() where !builds.contains(where: { $0.path == file }) {
            Self.admission.check(["\(file) no longer builds a ToolOutputGuard; remove it from toolOutputGuardBuilders"])
        }
    }

    func testNoWriterPassesTheBrowseListOrNothingAsProtection() {
        Self.admission.check(SourceTree.matches(Self.browseListAsProtection, in: Self.appSourceFiles),
                             "passes the browse list (or nothing) as write protection, which leaves Vault roots writable while Vault is off")
    }

    /// Existing `try? …loadSettings()` sites are counted per file; a file may lose sites, never gain them.
    func testNoNewTryOptionalSettingsLoads() {
        let sites = Dictionary(grouping: SourceTree.matches(Self.tryOptionalSettingsLoad, in: Self.appSourceFiles), by: \.path)
        for file in Set(sites.keys).union(Self.tryOptionalSettingsLoadBaseline.keys).sorted() {
            let count = sites[file]?.count ?? 0
            let allowed = Self.tryOptionalSettingsLoadBaseline[file] ?? 0
            Self.settingsForWrite.require(count <= allowed, "\(file) has \(count) `try? …loadSettings()` (baseline \(allowed)): \(sites[file] ?? [])")
            Self.settingsForWrite.require(count >= allowed,
                                          "\(file) has \(count) `try? …loadSettings()`, below its baseline \(allowed); lower or remove its entry in tryOptionalSettingsLoadBaseline")
        }
    }

    /// The detectors must catch the shipped mistakes, or they guard nothing.
    func testDetectorsCatchTheShippedMistakes() {
        func hits(_ pattern: String, _ line: String, _ view: SourceTree.View = .code) -> Int {
            SourceTree.matches(SourceTree.regex(pattern), in: view == .code ? SourceLex.stripped(line) : SourceLex.strippedCommentsOnly(line)).count
        }
        // 604025d^: the converter, downloader and recorder protected the browse list.
        let converter = "try OutputWriteGuard().validateCanWriteOutput(to: settings.outputFolder.url, archiveRoots: settings.archiveRoots.map(\\.url))"
        XCTAssertEqual(hits(Self.outputWriteGuardUse, converter), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, converter), 1)
        // fda0cb9^: exports and New Song protected only the browsed roots.
        XCTAssertEqual(hits(Self.browseListAsProtection, "try policy.enforceNoWrite(at: destination, archiveRoots: roots)"), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, "var created = try NewSongFolderCreator.create(request: request, protectedRoots: roots)"), 1)
        // The archive owners (2026-10-25) hold the browse list behind a receiver or a host closure.
        XCTAssertEqual(hits(Self.browseListAsProtection, "try policy.enforceNoWrite(at: destination, archiveRoots: host.roots())"), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, "NewSongFolderCreator.create(request: request, protectedRoots: library.roots)"), 1)
        XCTAssertEqual(hits(Self.browseListAsProtection, "NewSongFolderCreator.create(request: request, protectedRoots: viewModel.library.roots)"), 1)
        // e2135e6^: the recorder took its destination and roots from defaults on a failed load.
        XCTAssertEqual(hits(Self.tryOptionalSettingsLoad, "let settings = (try? context.settingsStore.loadSettings()) ?? .default"), 1)

        // b5fb166^: the converter built its own guard next to its own folder read.
        XCTAssertEqual(hits(Self.toolOutputGuardConstruction, "try ToolOutputGuard(settings: settings).validate(settings.outputFolder.url)", .codeAndStrings), 1)
        XCTAssertEqual(hits(Self.toolOutputGuardConstruction, #"log("refused by \(ToolOutputGuard (settings: settings))")"#, .codeAndStrings), 1, "inside an interpolation")
        XCTAssertEqual(hits(Self.toolOutputGuardConstruction, "let destination = try ToolOutputDestination.load(from: context.settingsStore)", .codeAndStrings), 0)
        XCTAssertEqual(hits(Self.toolOutputGuardConstruction, "public let outputGuard: ToolOutputGuard", .codeAndStrings), 0)
        XCTAssertEqual(hits(Self.toolOutputGuardConstruction, "/// only through `ToolOutputGuard(settings:)`.", .codeAndStrings), 0)

        XCTAssertEqual(hits(Self.outputWriteGuardUse, "try ToolOutputGuard(settings: settings).validate(folder)"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "archiveRoots: try writeProtectedRoots(),"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "archiveRoots: try host.writeProtectedRoots(),"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "protectedRoots: try library.writeProtectedRoots())"), 0)
        XCTAssertEqual(hits(Self.browseListAsProtection, "public init(folder: URL, protectedRoots: [URL]) {"), 0)
        XCTAssertEqual(hits(Self.tryOptionalSettingsLoad, "let settings = try settingsStore.loadSettings()"), 0)
    }
}
