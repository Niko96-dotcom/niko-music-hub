import AppCore
import XCTest

/// How a tool runs its work. Work the person waits for runs as a `JobRunner` job: the runner puts it in
/// the jobs strip, routes Esc and ⌘. by its cancel target and keeps quit waiting until the operation
/// unwinds (ADR-019). A tool's own `Task` sees none of that unless it registers with
/// `ShellJobStatusCenter.setExtraJob` by hand. Own tasks outside the registry shipped three times:
/// recorder takes and helper installs (061ea81) and the download's title lookup (c69717f) were cut off
/// by quit. Types cannot see an unregistered `Task`, so this test lists every task a tool creates, keyed
/// by the declaration it sits in, with its reason, and keeps the extra sources a closed list of named
/// exceptions. AGENTS.md row "Tool runs"; docs/architecture.md § How a tool runs its work.
final class ToolWorkSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Tool runs",
        why: "A tool's own Task is outside the jobs strip, Esc routing and the quit wait; three such runs were cut off by quit",
        see: "AGENTS.md row \"Tool runs\"; docs/architecture.md § How a tool runs its work",
        fix: "Run work the person waits for as a job (ToolContext.jobRunner.enqueue); list a Task in taskSites only for view-local async or a step its job or take awaits and cancels"
    )

    func testEveryTaskInAToolIsListedWithItsReason() {
        var problems: [String] = []
        var seen: Set<String> = []
        for file in Self.toolSourceFiles {
            let found = Self.taskSites(in: SourceTree.read(file, .code))
            let listed = (Self.taskSites[file] ?? []).map(\.declaration)
            if !found.isEmpty { seen.insert(file) }
            for declaration in Self.subtracting(listed, from: found.map(\.declaration)) {
                let lines = found.filter { $0.declaration == declaration }.map { "\(file):\($0.line)" }
                problems.append("\(lines.joined(separator: ", ")): unlisted Task in \(declaration)")
            }
            for declaration in Self.subtracting(found.map(\.declaration), from: listed) {
                problems.append("\(file): taskSites lists a Task in \(declaration) that is not there; remove its entry")
            }
        }
        for file in Set(Self.taskSites.keys).subtracting(seen).sorted() {
            problems.append("\(file): no Task left; remove it from taskSites")
        }
        Self.rule.check(problems.sorted())
    }

    /// A new tool does not add an extra source: it enqueues a job. Each extra source is a named exception
    /// with the reason it is not a job and the one place that registers it. `setExtraJob(sourceID:)` takes
    /// only a `ShellJobExtraSourceID` case, so the compiler refuses an unnamed source; this test keeps a
    /// reason and an owner for every case.
    func testExtraSourcesAreTheNamedExceptions() {
        let declared = Set(ShellJobExtraSourceID.allCases.map { String(describing: $0) })
        Self.rule.require(declared == Set(Self.extraSources.keys),
                          "ShellJobExtraSourceID has \(declared.sorted()) but extraSources lists \(Self.extraSources.keys.sorted()); a real exception gets its reason here and in the docs")
        let registration = SourceTree.regex(#"(?<!func )\bsetExtraJob\s*\(\s*sourceID\s*:\s*([^,)]*)"#)
        for file in SourceTree.swiftFiles(under: "Sources/") {
            let source = SourceTree.read(file, .codeAndStrings) as NSString
            for match in registration.matches(in: source as String, range: NSRange(location: 0, length: source.length)) {
                let argument = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let unprefixed = argument.hasPrefix("ShellJobExtraSourceID") ? String(argument.dropFirst("ShellJobExtraSourceID".count)) : argument
                let at = "\(file):\(SourceTree.lineNumber(of: match.range.location, in: source))"
                guard unprefixed.hasPrefix("."), let owner = Self.extraSources[String(unprefixed.dropFirst())]?.owner else {
                    Self.rule.check(["\(at): setExtraJob(sourceID: \(argument)) does not name its case, so its owner cannot be checked"])
                    continue
                }
                Self.rule.require(file.hasPrefix(owner), "\(at) registers ShellJobExtraSourceID\(unprefixed), which belongs to \(owner)")
            }
        }
    }

    /// The detector counts the ways this code base starts an unstructured `Task`, and no type
    /// position. It does not see SwiftUI's `.task {}` (cancelled with its view), structured child
    /// tasks (`async let`, task groups), `DispatchQueue.async`, or a `.init {}` whose `Task` type
    /// is inferred from a return type.
    func testDetectorCountsTaskConstructionsOnly() {
        func hits(_ line: String) -> Int {
            Self.taskSites(in: SourceLex.stripped(line)).count
        }
        XCTAssertEqual(hits("recordingTask = Task {"), 1)
        XCTAssertEqual(hits("Task { @MainActor [weak self] in"), 1)
        XCTAssertEqual(hits("let task = Task<RecorderResult, any Error> { [self] in"), 1)
        XCTAssertEqual(hits("let t = Task<Result<Int, any Error>, Never> { .success(1) }"), 1)
        XCTAssertEqual(hits("Task(priority: .high) {"), 1)
        XCTAssertEqual(hits("Task.detached { [self] in"), 1)
        XCTAssertEqual(hits("await Task.detached(priority: .utility) { () -> Int in"), 1)
        XCTAssertEqual(hits("Task.immediate { await run() }"), 1)
        XCTAssertEqual(hits("Task.init { await run() }"), 1)
        XCTAssertEqual(hits("register(task: Task { await run() })"), 1)
        XCTAssertEqual(hits("case .start: Task { await run() }"), 1)
        XCTAssertEqual(hits("let t = flag ? nil : Task { }"), 1)
        XCTAssertEqual(hits(#"let tasks = ["run": Task { }]"#), 1)
        XCTAssertEqual(hits("let t: Task<Void, Never> = .init { }"), 1)
        XCTAssertEqual(hits("let t: Task<Result<Int, any Error>, Never>? = .detached { .success(1) }"), 1)

        XCTAssertEqual(hits("private func startProbe(_ tool: HelperTool) -> Task<HelperToolStatus, Never> {"), 0)
        XCTAssertEqual(hits("var current: Task<Result<Int, any Error>, Never> {"), 0)
        XCTAssertEqual(hits("init(task: Task<RecorderResult, any Error>) {"), 0)
        XCTAssertEqual(hits("private var conversionTask: Task<[BatchAudioConversionOutcome], Never>?"), 0)
        XCTAssertEqual(hits("case awaitStop(Task<RecorderResult, any Error>)"), 0)
        XCTAssertEqual(hits("group.addTask {"), 0)
        XCTAssertEqual(hits("await withTaskCancellationHandler {"), 0)
        XCTAssertEqual(hits("try await Task.sleep(for: .seconds(1))"), 0)
        XCTAssertEqual(hits("guard !Task.isCancelled else { return }"), 0)
        XCTAssertEqual(hits("// `Task {}` is unstructured"), 0)
        XCTAssertEqual(hits(#"log("Task {")"#), 0)
    }

    /// A site is named by the declaration around it, so a listed reason belongs to that site.
    func testSitesAreNamedByTheirEnclosingDeclaration() {
        let source = """
        final class Model {
            private var task: Task<Void, Never>?

            deinit {
                Task { @MainActor in clear() }
            }

            func start() {
                let cancel: () -> Void = {
                    Task { await stop() }
                }
                task = Task {
                    await run()
                }
            }

            var body: some View {
                Button("Go") {
                    Task { await go() }
                }
            }

            private func multiLine(
                value: Int
            ) async {
                await run(progress: { _ in
                    Task { @MainActor in apply() }
                })
            }

            func oneLiner() { Task { } }
        }
        """
        XCTAssertEqual(
            Self.taskSites(in: SourceLex.stripped(source)).map(\.declaration),
            ["deinit", "start", "start", "body", "multiLine", "oneLiner"]
        )
    }

    // MARK: - The list

    /// Work that runs outside `JobRunner` and registers with `setExtraJob` by hand: the
    /// only files that may register it, and why it is not a job.
    static let extraSources: [String: (owner: String, reason: String)] = [
        "converter": (
            "Sources/FeatureAudioConverter/",
            "the jobs strip names the file in flight and carries a cancel help, which a job's fixed title "
                + "cannot; a job needs title updates and a cancel help, and the view model would observe it "
                + "the way Stem Separation does"
        ),
        "audioRecorder": (
            "Sources/FeatureAudioRecorder/",
            "a live take runs until the person stops it, keeps its own Stop control (unlisted) and is saved, "
                + "not cancelled, at quit"
        ),
        "downloadStart": (
            "Sources/FeatureDownloader/",
            "the title lookup names the job, so it runs before enqueue; the job covers the rest"
        ),
        "helperInstall": (
            "Sources/AppCore/HelperTools/",
            "shell work with no tool, its progress stays in Set Up (unlisted); runner jobs are always listed"
        ),
        "archiveScan": (
            "Sources/FeatureArchiveBrowser/",
            "shell work of the archive, not a tool run; read-only, so it does not block quit"
        ),
        "vaultTransfer": (
            "Sources/FeatureArchiveBrowser/",
            "the Project Vault queue (ProjectVaultOperationCoordinator) owns its order, retries and stop sheet"
        ),
    ]

    /// Every `Task` a tool creates, keyed by the declaration it sits in, with its reason. A run that
    /// is an extra source says so; everything else is view-local async or a step that its job or
    /// take awaits and cancels. The Settings recovery and restore-drill runs are the one known gap.
    static let taskSites: [String: [(declaration: String, reason: String)]] = [
        "Sources/AppCore/HelperTools/HelperToolHealth.swift": [
            ("startProbe", "a helper probe; callers await it, a newer probe supersedes it"),
        ],
        "Sources/AppCore/HelperTools/HelperToolSetupModel.swift": [
            ("install", "the install run, extra source helperInstall"),
            ("installMissing", "the install run, extra source helperInstall"),
            ("registerRunForQuit", "quit cancel: main-actor hop to cancelInstalls()"),
            ("performInstall", "install progress: main-actor hop to the row state"),
        ],
        "Sources/FeatureAudioConverter/AudioConverterView.swift": [
            ("queueRowContent", "Choose FFmpeg: the file chooser and the probe of the chosen file"),
            ("handleDrop", "drop intake: main-actor hop from the item provider"),
        ],
        "Sources/FeatureAudioConverter/AudioConverterViewModel.swift": [
            ("launchConversion", "the conversion run, extra source converter"),
            ("performConversion", "per-file progress: main-actor hop to the rows"),
            ("publishShellJobStatus", "jobs-strip cancel: main-actor hop to cancelConversion()"),
        ],
        "Sources/FeatureAudioRecorder/AudioRecorderView.swift": [
            ("body", "the page's Stop key: calls the view model"),
            ("toggleRecording", "stop"),
            ("toggleRecording", "start"),
            ("permissionSection", "start after the permission prompt"),
            ("errorCard", "start again"),
        ],
        "Sources/FeatureAudioRecorder/AudioRecorderViewModel.swift": [
            ("deinit", "main-actor hop that clears the capture signal"),
            ("startRecording", "the live take, extra source audioRecorder"),
            ("startRecording", "the take's stream ended: stop from outside the task it runs in"),
            ("registerTakeForQuit", "quit cancel: main-actor hop to stopRecording()"),
        ],
        "Sources/FeatureAudioRecorder/CoreAudioTapAdapter.swift": [
            ("beginStopLocked", "the stop flight of a take; stopRecording() awaits it"),
        ],
        "Sources/FeatureAudioRecorder/ResilientSystemAudioRecordingSession.swift": [
            ("start", "writer error callback: hop into the session actor"),
            ("makeCallbacks", "route change callback: hop into the session actor"),
            ("makeCallbacks", "backend failure callback: hop into the session actor"),
            ("scheduleRouteRecovery", "route recovery debounce, cancelled on stop"),
            ("wait", "PCM readiness timeout"),
        ],
        "Sources/FeatureAudioRecorder/SystemAudioCapturePermissionProbe.swift": [
            ("probe", "the probe's tap observer; the latch stops it after the deadline"),
            ("probe", "the probe's deadline timer"),
        ],
        "Sources/FeatureBPMTapper/BPMTapperView.swift": [
            ("animateTapPress", "tap press animation"),
        ],
        "Sources/FeatureDownloader/DownloaderViewModel.swift": [
            ("urlTextDidChange", "URL check debounce"),
            ("startDownload", "the title lookup before enqueue, extra source downloadStart"),
            ("observeJob", "observes the download job"),
            ("beginDownloadProgressFeedback", "slow-download hint ticker while the job runs"),
        ],
        "Sources/FeatureStemSeparation/DemucsMLXBackend.swift": [
            ("separate", "the separation inside the job's operation; the job's cancel is forwarded to it"),
        ],
        "Sources/FeatureStemSeparation/StemSeparationView.swift": [
            ("intakeCard", "drop intake: loads the dropped file URLs"),
        ],
        "Sources/FeatureStemSeparation/StemSeparationViewModel.swift": [
            ("performDrop", "drop intake: loads the dropped file URLs"),
            ("refreshHelperHealth", "Try Again: probes demucs-mlx"),
            ("observe", "observes the separation job"),
        ],
        "Sources/NikoMusicHub/DevTool/DevToolFeature.swift": [
            ("runSampleJob", "refreshes the job list after the sample job, which runs as a job"),
        ],
        "Sources/NikoMusicHub/Settings/ProjectVaultRecoverySection.swift": [
            ("exportRecovery", "known gap: the recovery bundle export is not registered, so quit can cut it off"),
            ("exportRecovery", "the export's file work off the main actor, awaited by the run above"),
            ("importRecovery", "known gap: the recovery import is not registered, so quit can cut it off"),
            ("importRecovery", "the import's file work off the main actor, awaited by the run above"),
            ("launchRecoveredLibrary", "main-actor hop from the open-application callback"),
        ],
        "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift": [
            ("runRestoreDrill", "known gap: the test restore runs unregistered on its own temp fixture"),
        ],
    ]

    // MARK: - Detectors

    struct TaskSite: Equatable {
        let line: Int
        let declaration: String
    }

    /// A generic argument list, one level of nesting deep (`Task<Result<Int, any Error>, Never>`).
    private static let generic = #"<(?:[^<>\n]|<[^<>\n]*>)*>"#

    /// `Task {`, `Task<…> {`, `Task(…)`; `Task.init`, `Task.immediate`, `Task.detached`; and
    /// `: Task<…> = .init/.immediate/.detached`.
    private static let taskConstruction = SourceTree.regex(
        #"\bTask\s*(?:"# + generic + #")?\s*[{(]|\bTask\s*\.\s*(?:init|immediate|detached)\b|:\s*Task\s*"#
            + generic + #"\s*\??\s*=\s*\.(?:init|immediate|detached)\b"#
    )

    /// `-> Task<…> {` and `var name: Task<…> {` are a return type and a computed property's type.
    private static let typePosition = SourceTree.regex(#"(?:->|\bvar\s+\w+\s*:)\s*$"#)

    private static let declaration = SourceTree.regex(
        #"^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|static|class|override|final|nonisolated|convenience|mutating|required|lazy)(?:\([^)]*\))?\s+)*(?:func\s+(\w+)|(init)\b|(deinit)\b|var\s+(\w+)|subscript\b|(?:class|struct|actor|enum|extension)\s+(\w+))"#
    )

    /// Every task construction in `strippedSource`, named by its enclosing declaration: the
    /// nearest line above, at a smaller indent, that declares a function, initializer, `deinit`,
    /// variable or type (or a `func`/`init`/`deinit` earlier on the same line). It relies on the
    /// code's consistent indentation, which the formatter keeps.
    static func taskSites(in strippedSource: String) -> [TaskSite] {
        let ns = strippedSource as NSString
        let lines = strippedSource.components(separatedBy: "\n")
        return taskConstruction.matches(in: strippedSource, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let before = ns.substring(to: match.range.location)
            let lineIndex = before.components(separatedBy: "\n").count - 1
            let prefix = String(before.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
            if ns.substring(with: match.range).hasPrefix("Task"),
               typePosition.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) != nil {
                return nil
            }
            return TaskSite(line: lineIndex + 1, declaration: enclosingDeclaration(lineIndex: lineIndex, prefix: prefix, lines: lines))
        }
    }

    private static func enclosingDeclaration(lineIndex: Int, prefix: String, lines: [String]) -> String {
        if let name = declaredName(in: prefix, functionsOnly: true) { return name }
        var indent = indentation(of: lines[lineIndex])
        var index = lineIndex - 1
        while index >= 0 {
            let line = lines[index]
            index -= 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A line that starts with `)` closes a multi-line signature or call; its opening line names it.
            guard !trimmed.isEmpty, !trimmed.hasPrefix(")"), indentation(of: line) < indent else { continue }
            indent = indentation(of: line)
            if let name = declaredName(in: line) { return name }
        }
        return "top level"
    }

    /// The name `line` declares; with `functionsOnly`, only a `func`, `init` or `deinit` (groups 1–3).
    private static func declaredName(in line: String, functionsOnly: Bool = false) -> String? {
        let ns = line as NSString
        guard let match = declaration.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups = functionsOnly ? 1..<4 : 1..<match.numberOfRanges
        for group in groups where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return functionsOnly ? nil : "subscript"
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    /// `values` minus one occurrence of each element of `removed`.
    private static func subtracting(_ removed: [String], from values: [String]) -> [String] {
        var remaining = values
        for value in removed {
            if let index = remaining.firstIndex(of: value) { remaining.remove(at: index) }
        }
        return Array(Set(remaining)).sorted()
    }

    /// Every tool's sources: the `Feature*` targets but the archive browser (shell work, not a tool run),
    /// the shell's helper installer, and the app target's two tool features (Settings, the Dev Tool).
    private static var toolSourceFiles: [String] {
        let files = SourceTree.swiftFiles(under: "Sources/").filter { file in
            (file.hasPrefix("Sources/Feature") && !file.hasPrefix("Sources/FeatureArchiveBrowser/"))
                || file.hasPrefix("Sources/AppCore/HelperTools/")
                || file.hasPrefix("Sources/NikoMusicHub/DevTool/")
                || file.hasPrefix("Sources/NikoMusicHub/Settings/")
        }
        XCTAssertGreaterThan(files.count, 30, "Sources/ walk found too few tool files")
        return files
    }
}
