import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class SongStatusHistoryListTests: XCTestCase {
    func testRowsShowNewestChangeFirstWithStableIDs() {
        let older = Date(timeIntervalSinceReferenceDate: 1_000)
        let newer = Date(timeIntervalSinceReferenceDate: 2_000)
        let history = [
            WorkflowStatusChange(songID: "/tmp/a", fromStatus: nil, toStatus: .prod, changedAt: older),
            WorkflowStatusChange(songID: "/tmp/a", fromStatus: .prod, toStatus: .done, changedAt: older),
            WorkflowStatusChange(songID: "/tmp/a", fromStatus: .done, toStatus: .prod, changedAt: newer),
        ]

        let rows = SongStatusHistoryList(history: history).rows

        XCTAssertEqual(rows.map(\.change.changedAt), [newer, older, older])
        XCTAssertEqual(rows.map(\.change.toStatus), [.prod, .done, .prod])
        XCTAssertEqual(rows.map(\.id), ["2000.0#0", "1000.0#1", "1000.0#0"])
    }
}
