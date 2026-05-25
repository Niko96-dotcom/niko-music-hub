import FeatureBPMTapper
import XCTest

@MainActor
final class BPMTapperActionsTests: XCTestCase {
    func testHalfTimeChangesDisplayedBPM() throws {
        let viewModel = makeViewModel()
        tap120BPM(on: viewModel)

        viewModel.setAdjustment(.halfTime)

        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), 60.0, accuracy: 0.001)
    }

    func testDoubleTimeChangesDisplayedBPM() throws {
        let viewModel = makeViewModel()
        tap120BPM(on: viewModel)

        viewModel.setAdjustment(.doubleTime)

        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), 240.0, accuracy: 0.001)
    }

    func testCopyWritesPlainDisplayedNumber() {
        let clipboard = FakeClipboard()
        let viewModel = makeViewModel(clipboard: clipboard)
        tap120BPM(on: viewModel)

        viewModel.copyDisplayedBPM()

        XCTAssertEqual(clipboard.copiedValues, ["120"])
        XCTAssertEqual(viewModel.copyConfirmation, "BPM copied")
    }

    func testCopyRoundsDisplayedBPMToWholeNumber() {
        let clipboard = FakeClipboard()
        let viewModel = makeViewModel(clipboard: clipboard)
        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.52)

        viewModel.copyDisplayedBPM()

        XCTAssertEqual(clipboard.copiedValues, ["115"])
    }

    func testSaveStoresAdjustmentContext() throws {
        let store = FakeHistoryStore()
        let viewModel = makeViewModel(store: store)
        tap120BPM(on: viewModel)
        viewModel.setAdjustment(.halfTime)

        viewModel.saveDisplayedBPM()

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.bpm, 60.0, accuracy: 0.001)
        XCTAssertEqual(entry.rawTappedBPM, 120.0, accuracy: 0.001)
        XCTAssertEqual(entry.adjustment, .halfTime)
        XCTAssertEqual(viewModel.saveConfirmation, "BPM saved")
        XCTAssertEqual(viewModel.historyEntries.count, 1)
    }

    func testCopySavedBPMUsesRowValue() {
        let clipboard = FakeClipboard()
        let viewModel = makeViewModel(clipboard: clipboard)
        let entry = BPMHistoryEntry(
            bpm: 127.5,
            rawTappedBPM: 255.0,
            adjustment: .halfTime,
            timestamp: Date(timeIntervalSince1970: 20)
        )

        viewModel.copySavedBPM(entry)

        XCTAssertEqual(clipboard.copiedValues, ["128"])
        XCTAssertEqual(viewModel.copyConfirmation, "BPM copied")
    }

    func testClearHistoryDoesNotResetCurrentRun() throws {
        let store = FakeHistoryStore(entries: [
            BPMHistoryEntry(
                bpm: 120.0,
                rawTappedBPM: 120.0,
                adjustment: .original,
                timestamp: Date(timeIntervalSince1970: 10)
            )
        ])
        let viewModel = makeViewModel(store: store)
        tap120BPM(on: viewModel)
        try viewModel.loadHistory()

        viewModel.clearHistory()

        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(viewModel.historyEntries, [])
        XCTAssertEqual(try XCTUnwrap(viewModel.rawBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.tapCount, 2)
    }

    private func makeViewModel(
        store: FakeHistoryStore = FakeHistoryStore(),
        clipboard: FakeClipboard = FakeClipboard()
    ) -> BPMTapperViewModel {
        BPMTapperViewModel(historyStore: store, clipboard: clipboard)
    }

    private func tap120BPM(on viewModel: BPMTapperViewModel) {
        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.5)
    }
}

private final class FakeHistoryStore: BPMHistoryStore, @unchecked Sendable {
    private(set) var entries: [BPMHistoryEntry]

    init(entries: [BPMHistoryEntry] = []) {
        self.entries = entries
    }

    func listEntries() throws -> [BPMHistoryEntry] {
        entries
    }

    func addEntry(_ entry: BPMHistoryEntry) throws {
        entries.insert(entry, at: 0)
    }

    func clearEntries() throws {
        entries = []
    }
}

private final class FakeClipboard: BPMClipboardWriting, @unchecked Sendable {
    private(set) var copiedValues: [String] = []

    func copyPlainNumber(_ value: String) {
        copiedValues.append(value)
    }
}
