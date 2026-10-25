import XCTest
@testable import NikoMusicCore

final class VaultRestorePhaseTests: XCTestCase {
    /// A frozen copy of the table: changing an edge means changing this test.
    func testEveryPhaseHasExactlyTheFrozenNextPhases() throws {
        let expected: [VaultRestorePhase: Set<VaultRestorePhase>] = [
            .materializingArchive: [.copyingToActiveStaging, .superseded],
            .copyingToActiveStaging: [.verifyingActiveStaging, .materializingArchive, .superseded],
            .verifyingActiveStaging: [.promotingActiveCopy, .superseded],
            .promotingActiveCopy: [.persistingActiveLocation, .superseded],
            .persistingActiveLocation: [.openingInCubase, .superseded],
            .openingInCubase: [.superseded],
            .superseded: [],
        ]
        XCTAssertEqual(Set(expected.keys), Set(VaultRestorePhase.allCases))
        for phase in VaultRestorePhase.allCases {
            XCTAssertEqual(VaultRestorePhase.allowedNextPhases[phase], expected[phase], "\(phase)")
            for next in expected[phase] ?? [] {
                XCTAssertEqual(try phase.checkedChange(to: next), next)
            }
        }
    }

    /// Every phase change the restore suites made (step 1 of the state
    /// machine plan) is legal.
    func testTableContainsEveryObservedEdge() {
        for edge in VaultObservedEdges.restore {
            XCTAssertNoThrow(try edge.from.checkedChange(to: edge.to), "missing \(edge)")
        }
    }

    /// A record's phase changes only through `changePhase(to:)`, which takes the change from the
    /// table: from every phase to every phase, a listed change moves the record and an unlisted one
    /// throws and leaves the record as it was. A new record starts in `materializingArchive`.
    func testRecordPhaseChangesOnlyThroughTheTable() throws {
        func record(in phase: VaultRestorePhase?) -> VaultRestoreRecord {
            let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            let projectID = ProjectID()
            let generation = URL(fileURLWithPath: "/Vault/generation", isDirectory: true)
            let staging = URL(fileURLWithPath: "/Active/staging", isDirectory: true)
            let destination = URL(fileURLWithPath: "/Active/Song", isDirectory: true)
            let manifest = VaultManifest(id: id, createdAt: Date(timeIntervalSinceReferenceDate: 0), entries: [])
            guard let phase else {
                return VaultRestoreRecord(
                    id: id, projectID: projectID, archiveGenerationURL: generation, stagingURL: staging,
                    destinationURL: destination, manifest: manifest
                )
            }
            return VaultRestoreRecord(
                id: id, projectID: projectID, archiveGenerationURL: generation, stagingURL: staging,
                destinationURL: destination, manifest: manifest, phase: phase
            )
        }
        XCTAssertEqual(record(in: nil).phase, .materializingArchive)
        for phase in VaultRestorePhase.allCases {
            for next in VaultRestorePhase.allCases {
                var changed = record(in: phase)
                let before = changed
                if VaultRestorePhase.allowedNextPhases[phase, default: []].contains(next) {
                    try changed.changePhase(to: next)
                    XCTAssertEqual(changed.phase, next, "\(phase) -> \(next)")
                } else {
                    XCTAssertThrowsError(try changed.changePhase(to: next), "\(phase) -> \(next)") {
                        XCTAssertEqual($0 as? VaultTransitionError, .illegalRestorePhase(from: phase, to: next))
                    }
                    XCTAssertEqual(changed, before, "a refused change keeps the record: \(phase) -> \(next)")
                }
            }
        }
    }

    func testTableRejectsChangesNoPathMakes() {
        let illegal: [VaultRestoreEdge] = [
            .init(.materializingArchive, .promotingActiveCopy),
            .init(.verifyingActiveStaging, .copyingToActiveStaging),
            .init(.promotingActiveCopy, .materializingArchive),
            .init(.openingInCubase, .persistingActiveLocation),
            .init(.superseded, .materializingArchive),
            .init(.superseded, .superseded),
        ]
        for edge in illegal {
            XCTAssertThrowsError(try edge.from.checkedChange(to: edge.to), "\(edge)") {
                XCTAssertEqual($0 as? VaultTransitionError, .illegalRestorePhase(from: edge.from, to: edge.to))
            }
        }
    }
}
