import AppCore
import XCTest

@MainActor
final class QuickAccessRouterTests: XCTestCase {

    // MARK: - .openTool routing

    func testExecuteOpenToolPublishesToolRequest() {
        let router = QuickAccessRouter()
        router.execute(.openTool("stem-separation"))
        XCTAssertEqual(router.requestedToolID, "stem-separation")
        XCTAssertEqual(router.toolRequest?.sequence, 1)
    }

    func testExecuteOpenToolPublishesNewRequest() {
        let router = QuickAccessRouter()
        router.execute(.openTool("bpm-tapper"))
        let first = router.toolRequest
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.requestedToolID, "wav-converter")
        XCTAssertNotEqual(router.toolRequest?.sequence, first?.sequence)
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

    func testExecuteRevealOutputInboxDoesNotRequestATool() {
        let router = QuickAccessRouter()
        router.execute(.revealOutputInbox)
        XCTAssertNil(router.toolRequest)
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
        XCTAssertNil(router.toolRequest)
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testExecuteOpenAppDoesNotReplaceToolRequest() {
        let router = QuickAccessRouter()
        router.execute(.openTool("bpm-tapper"))
        router.execute(.openApp)
        XCTAssertEqual(router.requestedToolID, "bpm-tapper")
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testExecuteQuitAppDoesNotReplaceToolRequest() {
        let router = QuickAccessRouter()
        router.execute(.openTool("downloader"))
        router.execute(.quitApp)
        XCTAssertEqual(router.requestedToolID, "downloader")
        XCTAssertFalse(router.revealOutputInbox)
    }

    // MARK: - Initial state

    func testInitialToolRequestIsNil() {
        let router = QuickAccessRouter()
        XCTAssertNil(router.toolRequest)
    }

    func testInitialRevealOutputInboxIsFalse() {
        let router = QuickAccessRouter()
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testFocusArchiveSearchSelectsExistingArchiveAndEmitsRepeatableFocusRequests() {
        let router = QuickAccessRouter()
        router.execute(.focusArchiveSearch)
        XCTAssertEqual(router.requestedToolID, "archive-browser")
        XCTAssertEqual(router.archiveSearchFocusRequest, 1)
        router.execute(.focusArchiveSearch)
        XCTAssertEqual(router.archiveSearchFocusRequest, 2)
        router.execute(.restoreProject)
        XCTAssertEqual(router.archiveSearchFocusRequest, 3)
    }

    func testExecuteFindIncrementsArchiveSearchFocusRequestAndSelectsArchiveBrowser() {
        let router = QuickAccessRouter()
        XCTAssertEqual(router.archiveSearchFocusRequest, 0)
        XCTAssertNil(router.toolRequest)
        router.execute(.focusArchiveSearch)
        XCTAssertEqual(router.requestedToolID, "archive-browser")
        XCTAssertEqual(router.archiveSearchFocusRequest, 1)
        let firstSequence = router.toolRequest?.sequence
        router.execute(.focusArchiveSearch)
        XCTAssertEqual(router.requestedToolID, "archive-browser")
        XCTAssertNotEqual(router.toolRequest?.sequence, firstSequence)
        XCTAssertEqual(router.archiveSearchFocusRequest, 2)
    }

    // MARK: - repeated one-shot requests

    func testExecuteSameToolIDTwicePublishesDistinctRequests() {
        let router = QuickAccessRouter()
        router.execute(.openTool("wav-converter"))
        let first = router.toolRequest
        router.execute(.openTool("wav-converter"))
        XCTAssertEqual(router.requestedToolID, "wav-converter")
        XCTAssertNotEqual(router.toolRequest?.sequence, first?.sequence)
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
