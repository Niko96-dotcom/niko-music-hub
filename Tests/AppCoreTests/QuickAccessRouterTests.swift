import AppCore
import Combine
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

    // MARK: - Converter handoff consume (regression: endless publish ping-pong)

    func testConsumePrefilledConverterURLsDoesNotPublishWhenEmpty() {
        let router = QuickAccessRouter()
        var emissions: [[URL]] = []
        let cancellable = router.$prefilledConverterURLs.dropFirst().sink { emissions.append($0) }
        defer { cancellable.cancel() }

        XCTAssertEqual(router.consumePrefilledConverterURLs(), [])
        XCTAssertEqual(router.consumePrefilledConverterURLs(), [])
        XCTAssertTrue(
            emissions.isEmpty,
            "consume on empty must not publish, got \(emissions.count) emissions"
        )
    }

    func testConsumeAfterOpenConverterReturnsURLsOnceWithoutExtraPublish() {
        let router = QuickAccessRouter()
        var emissions: [[URL]] = []
        let cancellable = router.$prefilledConverterURLs.dropFirst().sink { emissions.append($0) }
        defer { cancellable.cancel() }

        let url = URL(fileURLWithPath: "/tmp/Preview.wav")
        router.openConverter(with: [url])
        XCTAssertEqual(emissions.count, 1, "openConverter must publish the handoff once")

        let first = router.consumePrefilledConverterURLs()
        XCTAssertEqual(first, [url])
        XCTAssertEqual(emissions.count, 2, "first consume must publish the drain to empty")

        let second = router.consumePrefilledConverterURLs()
        XCTAssertEqual(second, [])
        XCTAssertEqual(
            emissions.count,
            2,
            "second consume on empty must not publish"
        )
    }

    // MARK: - Helper-tool Set Up sheet request

    func testRequestHelperToolSetupIncrementsOneShotCounter() {
        let router = QuickAccessRouter()
        XCTAssertEqual(router.helperSetupRequest, 0)
        router.requestHelperToolSetup()
        XCTAssertEqual(router.helperSetupRequest, 1)
        router.requestHelperToolSetup()
        XCTAssertEqual(router.helperSetupRequest, 2)
    }

}
