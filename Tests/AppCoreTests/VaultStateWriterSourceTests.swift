import XCTest

/// Every Vault state change goes through one checked write: the state table
/// refuses an unlisted edge before anything is saved. A direct assignment
/// would skip the table, and the journal would hold an edge nobody checked.
final class VaultStateWriterSourceTests: XCTestCase {
    /// The only assignments of a transfer's `state` outside an initializer.
    private static let writers: Set<String> = [
        "Sources/NikoMusicCore/Vault/LocalVaultTransferEngine.swift: record.state = try ProjectVaultStateMachine().applying(transition, to: record.state)",
    ]

    func testOnlyTheCheckedWritesAssignAState() throws {
        let root = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var writes: Set<String> = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
            let code = SourceLex.stripped(try String(contentsOf: url, encoding: .utf8))
            guard Self.holdsVaultRecords(relative, code) else { continue }
            scanned += 1
            writes.formUnion(Self.stateWrites(in: code).map { "\(relative): \($0)" })
        }
        XCTAssertGreaterThan(scanned, 20, "the scan found too few Vault files")
        XCTAssertEqual(writes, Self.writers, "change a Vault state through the engine's checkAndSave")
    }

    /// The detector must catch the direct writes the engine used before the
    /// checked write, and ignore comparisons, initializers and comments.
    func testDetectorCatchesDirectWrites() {
        let shipped = [
            "record.state = .archiveVerified",
            "migrated.state = .recoveryRequired",
            "record.state = recopy ? .copyingToArchiveStaging : origin",
            "$0.state=.superseded",
        ]
        for line in shipped {
            XCTAssertEqual(Self.stateWrites(in: line).count, 1, "Detector misses: \(line)")
        }
        let allowed = [
            "guard record.state == .archiveVerified else { return }",
            "self.state = state",
            "state = try values.decode(VaultTransferState.self, forKey: .state)",
            SourceLex.stripped("// record.state = .archiveVerified"),
        ]
        for line in allowed {
            XCTAssertEqual(Self.stateWrites(in: line), [], "Detector flags allowed code: \(line)")
        }
    }

    /// The Vault code, plus any other file that names a Vault record, store or engine.
    private static func holdsVaultRecords(_ relative: String, _ code: String) -> Bool {
        relative.hasPrefix("Sources/NikoMusicCore/") || relative.hasPrefix("Sources/AppCore/ProjectVault/")
            || ["VaultTransferRecord", "VaultTransferStoring", "LocalVaultTransferEngine"].contains {
                SourceLex.containsWord(code, $0)
            }
    }

    /// Each `x.state = …` line, trimmed; an initializer's `self.state = state` is no change.
    static func stateWrites(in code: String) -> [String] {
        code.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            line.range(of: #"\.state\s*=(?!=)"#, options: .regularExpression) != nil
                && line.range(of: #"^self\.state\s*=\s*state$"#, options: .regularExpression) == nil
        }
    }
}
