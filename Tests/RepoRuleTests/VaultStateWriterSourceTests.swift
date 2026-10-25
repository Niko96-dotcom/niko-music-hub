import XCTest

/// Every Vault state change goes through one checked write: the transfer state table or the restore
/// phase table refuses an unlisted edge before anything is saved. A direct assignment would skip the
/// table, and the journal would hold an edge nobody checked. The compiler keeps the writes in the
/// records' own files: `state` and `phase` are `private(set)`, so only `VaultTransferRecord.apply(_:)`
/// and `VaultRestoreRecord.changePhase(to:)` change a live record. This test keeps the setters private
/// and checks the one thing the compiler cannot: inside its own file, a record assigns its field (also
/// `inout` or through `self =`) only in the new record's start, the decoder and the checked writer.
/// AGENTS.md row "Vault records"; docs/architecture.md § Vault state changes.
final class VaultStateWriterSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Vault records",
        why: "A direct assignment of a transfer's state or a restore's phase skips the table, and the journal holds an unchecked edge",
        see: "AGENTS.md row \"Vault records\"; docs/architecture.md § Vault state changes",
        fix: "Change a transfer's state through apply(_:) and a restore's phase through changePhase(to:); keep both setters private(set)"
    )

    private static let transferRecord = "Sources/NikoMusicCore/Vault/VaultTransferRecord.swift"
    private static let restoreRecord = "Sources/NikoMusicCore/Vault/VaultRestoreRecord.swift"

    func testTheStateAndPhaseSettersStayPrivate() {
        Self.rule.expect(Self.transferRecord, matching: #"\n    public private\(set\) var state: VaultTransferState\n"#, "`state` with a private(set) setter")
        Self.rule.expect(Self.restoreRecord, matching: #"\n    public private\(set\) var phase: VaultRestorePhase\n"#, "`phase` with a private(set) setter")
    }

    /// The assignments each record file may hold: the start of a new record, the decoder (a journal row
    /// carries any state) and the checked writer, which takes the edge from the table.
    private static let allowed: [String: Set<String>] = [
        transferRecord: [
            "self.state = .activeLocal",
            "state = try values.decode(VaultTransferState.self, forKey: .state)",
            "state = try ProjectVaultStateMachine().applying(transition, to: state)",
        ],
        restoreRecord: [
            "self.phase = .materializingArchive",
            "phase = try values.decode(VaultRestorePhase.self, forKey: .phase)",
            "phase = try phase.checkedChange(to: next)",
        ],
    ]

    func testOnlyTheCheckedWriterAssignsInsideTheRecordFile() {
        for (file, allowed) in Self.allowed.sorted(by: { $0.key < $1.key }) {
            let writes = Set(Self.stateWrites(in: SourceTree.read(file, .code)))
            Self.rule.check(writes.subtracting(allowed).sorted().map { "\(file): `\($0)` assigns a state outside the checked writer" })
            Self.rule.check(allowed.subtracting(writes).sorted().map { "\(file): `\($0)` is gone; update the list of allowed assignments" })
        }
    }

    /// The detector must catch an assignment of the record's own field anywhere on a line, bare or
    /// through a value, an `inout` pass and a whole-value `self =`, and ignore comparisons, other fields,
    /// declarations and comments.
    func testDetectorCatchesAssignmentsOfTheField() {
        for line in [
            "state = .archiveVerified", "self.state = state", "copy.state = .recoveryRequired", "$0.phase=.superseded", "phase = next",
            "mutating func force(_ next: VaultTransferState) { state = next }",
            "if ok { state = next }",
            "case .stop: phase = .superseded",
            "Self.set(&state, next)",
            "swap(&self.phase, &other)",
            "self = other",
        ] {
            XCTAssertEqual(Self.stateWrites(in: line).count, 1, "Detector misses: \(line)")
        }
        for line in [
            "guard state == .archiveVerified else { return }",
            "self.archiveTransferState = archiveTransferState",
            "let phase = record.phase",
            "var state = record.state",
            "if self == other { return }",
            SourceLex.stripped("// state = .archiveVerified"),
        ] {
            XCTAssertEqual(Self.stateWrites(in: line), [], "Detector flags allowed code: \(line)")
        }
    }

    /// Each line that assigns `state` or `phase` anywhere (bare or as a member of a value, but not a
    /// `let`/`var` declaration), passes it `inout` (`&state`), or assigns `self` whole, trimmed.
    static func stateWrites(in code: String) -> [String] {
        let write = #"(?<![\w$.])(?<!\blet )(?<!\bvar )(?:[\w$?]+\.)?(?:state|phase)\s*=(?!=)"#
        let inoutPass = #"&\s*(?:[\w$?]+\.)?(?:state|phase)\b"#
        let wholeValue = #"\bself\s*=(?!=)"#
        return code.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            line.range(of: "\(write)|\(inoutPass)|\(wholeValue)", options: .regularExpression) != nil
        }
    }
}
