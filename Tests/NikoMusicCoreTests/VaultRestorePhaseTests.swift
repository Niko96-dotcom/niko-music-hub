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
