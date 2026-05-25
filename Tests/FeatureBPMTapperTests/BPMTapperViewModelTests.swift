import FeatureBPMTapper
import XCTest

@MainActor
final class BPMTapperViewModelTests: XCTestCase {
    func testInitialStatePromptsForTap() {
        let viewModel = BPMTapperViewModel()

        XCTAssertNil(viewModel.rawBPM)
        XCTAssertNil(viewModel.displayedBPM)
        XCTAssertEqual(viewModel.tapCount, 0)
        XCTAssertEqual(viewModel.statusText, "Tap the pad or press Space")
        XCTAssertEqual(viewModel.statusKind, .idle)
        XCTAssertFalse(viewModel.hasStartedRun)
    }

    func testSecondTapShowsFirstEstimate() throws {
        let viewModel = BPMTapperViewModel()

        viewModel.recordTap(at: 0.0)
        XCTAssertNil(viewModel.displayedBPM)

        viewModel.recordTap(at: 0.5)

        XCTAssertEqual(try XCTUnwrap(viewModel.rawBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.tapCount, 2)
        XCTAssertEqual(viewModel.statusText, "First estimate ready. Keep tapping to steady it.")
        XCTAssertEqual(viewModel.statusKind, .firstEstimate)
    }

    func testResetClearsCurrentRun() {
        let viewModel = BPMTapperViewModel()
        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.5)

        viewModel.resetTaps()

        XCTAssertNil(viewModel.rawBPM)
        XCTAssertNil(viewModel.displayedBPM)
        XCTAssertEqual(viewModel.tapCount, 0)
        XCTAssertEqual(viewModel.statusText, "Tap the pad or press Space")
        XCTAssertFalse(viewModel.hasStartedRun)
    }

    func testLongPauseShowsFreshRunStatus() {
        let viewModel = BPMTapperViewModel()
        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.5)

        viewModel.recordTap(at: 5.0)

        XCTAssertNil(viewModel.rawBPM)
        XCTAssertNil(viewModel.displayedBPM)
        XCTAssertEqual(viewModel.tapCount, 1)
        XCTAssertEqual(viewModel.statusText, "New tap run started.")
        XCTAssertEqual(viewModel.statusKind, .longPauseReset)
        XCTAssertTrue(viewModel.hasStartedRun)
    }

    func testOutlierKeepsPreviousDisplayedBPM() throws {
        let viewModel = BPMTapperViewModel()
        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.5)
        viewModel.recordTap(at: 1.0)
        viewModel.recordTap(at: 1.5)
        let previousBPM = try XCTUnwrap(viewModel.displayedBPM)

        viewModel.recordTap(at: 1.58)

        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), previousBPM, accuracy: 0.001)
        XCTAssertEqual(viewModel.statusText, "Ignored one uneven tap. Keep tapping.")
        XCTAssertEqual(viewModel.statusKind, .outlierIgnored)
    }
}
