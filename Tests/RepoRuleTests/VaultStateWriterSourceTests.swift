import XCTest

/// Every Vault state change goes through one checked write: the transfer state table or the restore
/// phase table refuses an unlisted edge before anything is saved. A direct assignment would skip the
/// table, and the journal would hold an edge nobody checked.
/// AGENTS.md row "Vault records"; docs/architecture.md § Vault state changes.
final class VaultStateWriterSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Vault records",
        why: "A direct assignment of a transfer's state or a restore's phase skips the table, and the journal holds an unchecked edge",
        see: "AGENTS.md row \"Vault records\"; docs/architecture.md § Vault state changes",
        fix: "Change a Vault state or phase through the engine's checkAndSave"
    )

    /// The only assignments of a transfer's `state` or a restore's `phase` outside an initializer: the
    /// two engines' `checkAndSave` and the store's launch reconcile.
    private static let writers: Set<String> = [
        "Sources/NikoMusicCore/Vault/LocalVaultTransferEngine.swift: record.state = try ProjectVaultStateMachine().applying(transition, to: record.state)",
        "Sources/NikoMusicCore/Vault/LocalVaultRestoreEngine.swift: record.phase = try record.phase.checkedChange(to: phase)",
        "Sources/NikoMusicCore/Persistence/SQLiteVaultTransferStore.swift: retired.phase = try loser.phase.checkedChange(to: .superseded)",
    ]

    func testOnlyTheCheckedWritesAssignAState() {
        let vaultFiles = SourceTree.swiftFiles(under: "Sources/").filter { Self.holdsVaultRecords($0, SourceTree.read($0, .code)) }
        XCTAssertGreaterThan(vaultFiles.count, 20, "the scan found too few Vault files")
        let writes = Set(vaultFiles.flatMap { file in Self.stateWrites(in: SourceTree.read(file, .code)).map { "\(file): \($0)" } })
        Self.rule.check(writes.subtracting(Self.writers).sorted().map { "\($0) assigns a state directly" })
        Self.rule.check(Self.writers.subtracting(writes).sorted().map { "\($0) is gone; update the list of checked writes" })
    }

    /// The detector must catch the direct writes the engine used before the checked write, and ignore
    /// comparisons, initializers and comments.
    func testDetectorCatchesDirectWrites() {
        let shipped = [
            "record.state = .archiveVerified",
            "migrated.state = .recoveryRequired",
            "record.state = recopy ? .copyingToArchiveStaging : origin",
            "$0.state=.superseded",
            "record.phase = .materializingArchive",
            "retired.phase = .superseded",
        ]
        for line in shipped {
            XCTAssertEqual(Self.stateWrites(in: line).count, 1, "Detector misses: \(line)")
        }
        let allowed = [
            "guard record.state == .archiveVerified else { return }",
            "self.state = state",
            "self.phase = phase",
            "$0.phase != .superseded",
            "state = try values.decode(VaultTransferState.self, forKey: .state)",
            SourceLex.stripped("// record.state = .archiveVerified"),
        ]
        for line in allowed {
            XCTAssertEqual(Self.stateWrites(in: line), [], "Detector flags allowed code: \(line)")
        }
    }

    /// The Vault code, plus any other file that names a Vault record, store or engine.
    private static func holdsVaultRecords(_ relative: String, _ code: String) -> Bool {
        relative.hasPrefix("Sources/NikoMusicCore/") || relative.hasPrefix("Sources/ProjectVaultRuntime/")
            || [
                "VaultTransferRecord", "VaultTransferStoring", "LocalVaultTransferEngine",
                "VaultRestoreRecord", "VaultRestoreStoring", "LocalVaultRestoreEngine",
            ].contains { SourceLex.containsWord(code, $0) }
    }

    /// Each `x.state = …` or `x.phase = …` line, trimmed; an initializer's `self.state = state` or
    /// `self.phase = phase` is no change.
    static func stateWrites(in code: String) -> [String] {
        code.split(separator: "\n").filter { $0.contains(".state") || $0.contains(".phase") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            line.range(of: #"\.(state|phase)\s*=(?!=)"#, options: .regularExpression) != nil
                && line.range(of: #"^self\.(state\s*=\s*state|phase\s*=\s*phase)$"#, options: .regularExpression) == nil
        }
    }
}
