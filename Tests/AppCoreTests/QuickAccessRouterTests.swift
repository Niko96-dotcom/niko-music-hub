import AppCore
import XCTest

@MainActor
final class QuickAccessRouterTests: XCTestCase {

    // MARK: - .openTool routing

    func testExecuteOpenToolSetsSelectedToolID() {
        let router = QuickAccessRouter()
        router.execute(.openTool("stem-separation"))
        XCTAssertEqual(router.selectedToolID, "stem-separation")
    }

    func testExecuteOpenToolOverwritesPreviousSelection() {
        let router = QuickAccessRouter()
        router.execute(.openTool("bpm-tapper"))
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.selectedToolID, "wav-converter")
    }

    func testExecuteOpenToolDoesNotAffectRevealFlag() {
        let router = QuickAccessRouter()
        router.execute(.openTool("downloader"))
        XCTAssertFalse(router.revealOutputInbox)
    }

    // MARK: - .revealOutputInbox routing

    func testExecuteRevealOutputInboxSetsFlag() {
        let router = QuickAccessRouter()
        router.execute(.revealOutputInbox)
        XCTAssertTrue(router.revealOutputInbox)
    }

    func testExecuteRevealOutputInboxDoesNotChangeSelectedToolID() {
        let router = QuickAccessRouter()
        router.execute(.revealOutputInbox)
        XCTAssertNil(router.selectedToolID)
    }

    func testClearRevealOutputInboxResetsFlag() {
        let router = QuickAccessRouter()
        router.execute(.revealOutputInbox)
        router.clearRevealOutputInbox()
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testClearRevealOutputInboxIsIdempotentWhenFlagAlreadyFalse() {
        let router = QuickAccessRouter()
        // flag is already false — calling clear must not crash
        router.clearRevealOutputInbox()
        XCTAssertFalse(router.revealOutputInbox)
    }

    // MARK: - .openApp routing (model-layer no-op in Phase 46)

    func testExecuteOpenAppIsNoOp() {
        let router = QuickAccessRouter()
        router.execute(.openApp)
        XCTAssertNil(router.selectedToolID)
        XCTAssertFalse(router.revealOutputInbox)
    }

    // MARK: - Initial state

    func testInitialSelectedToolIDIsNil() {
        let router = QuickAccessRouter()
        XCTAssertNil(router.selectedToolID)
    }

    func testInitialRevealOutputInboxIsFalse() {
        let router = QuickAccessRouter()
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testRestoreProjectSelectsExistingArchiveAndEmitsRepeatableFocusRequests() {
        let router = QuickAccessRouter()
        router.execute(.restoreProject)
        XCTAssertEqual(router.selectedToolID, "archive-browser")
        XCTAssertEqual(router.archiveSearchFocusRequest, 1)
        router.execute(.restoreProject)
        XCTAssertEqual(router.archiveSearchFocusRequest, 2)
    }

    // MARK: - clearSelectedToolID

    func testSelectedToolIDIsNilAfterClear() {
        let router = QuickAccessRouter()
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.selectedToolID, "wav-converter")
        router.clearSelectedToolID()
        XCTAssertNil(router.selectedToolID)
    }

    func testExecuteSameToolIDTwiceAfterClearBothFire() {
        let router = QuickAccessRouter()
        router.execute(.openTool("wav-converter"))
        router.clearSelectedToolID()
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.selectedToolID, "wav-converter")
    }

    func testClearSelectedToolIDIsIdempotentWhenAlreadyNil() {
        let router = QuickAccessRouter()
        // selectedToolID is already nil — calling clear must not crash
        router.clearSelectedToolID()
        XCTAssertNil(router.selectedToolID)
    }

    // MARK: - HAND-04: router does not call OutputHandoff

    func testRouterSourceDoesNotReferenceOutputHandoff() throws {
        let path = "Sources/AppCore/QuickAccess/QuickAccessRouter.swift"
        let source = try SourceTestSupport.read(path)
        XCTAssertFalse(
            source.contains("OutputHandoff"),
            "QuickAccessRouter must not reference OutputHandoff — HAND-04 boundary"
        )
    }
}
