import AppCore
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

    // NMH-043: the BPM error card's Try Again action retries the failed
    // storage work via retryAfterStorageError().
    func testRetryAfterStorageErrorRecoversWhenStoreRecovers() throws {
        let store = FlakyHistoryStore()
        let viewModel = BPMTapperViewModel(historyStore: store, clipboard: FakeClipboard())
        tap120BPM(on: viewModel)

        viewModel.saveDisplayedBPM()
        XCTAssertEqual(
            viewModel.errorText,
            "Could not save this BPM. Check local app storage, then try Save BPM again."
        )

        store.failAdds = false
        viewModel.retryAfterStorageError()

        XCTAssertNil(viewModel.errorText)
        XCTAssertEqual(viewModel.saveConfirmation, "BPM saved")
        XCTAssertEqual(viewModel.historyEntries.count, 1)
    }

    // NMH-043: retry keeps the storage error copy when the store still fails.
    func testRetryAfterStorageErrorKeepsErrorWhenStoreStillFails() {
        let store = FlakyHistoryStore()
        let viewModel = BPMTapperViewModel(historyStore: store, clipboard: FakeClipboard())
        tap120BPM(on: viewModel)

        viewModel.saveDisplayedBPM()
        viewModel.retryAfterStorageError()

        XCTAssertEqual(
            viewModel.errorText,
            "Could not save this BPM. Check local app storage, then try Save BPM again."
        )
    }

    // B1: unreadable history must surface once (not an empty list with
    // Clear disabled) and flag itself corrupt so Clear stays available.
    func testCorruptHistorySurfacesErrorAndFlagsClear() throws {
        let fixture = CorruptHistoryFixture()
        let viewModel = BPMTapperViewModel(
            historyStore: fixture.store,
            clipboard: FakeClipboard()
        )

        XCTAssertThrowsError(try viewModel.loadHistory())
        XCTAssertTrue(viewModel.hasCorruptHistory)
        XCTAssertEqual(viewModel.historyEntries, [])
        XCTAssertEqual(viewModel.errorText, BPMTapperViewModel.corruptHistoryMessage)
    }

    // B1: Clear discards the bad bytes without decoding and keeps the tap run.
    func testClearHistoryRecoversFromCorruptionKeepingTapRun() throws {
        let fixture = CorruptHistoryFixture()
        let viewModel = BPMTapperViewModel(
            historyStore: fixture.store,
            clipboard: FakeClipboard()
        )
        tap120BPM(on: viewModel)
        XCTAssertThrowsError(try viewModel.loadHistory())

        viewModel.clearHistory()

        XCTAssertNil(viewModel.errorText)
        XCTAssertFalse(viewModel.hasCorruptHistory)
        XCTAssertEqual(viewModel.historyEntries, [])
        XCTAssertEqual(try XCTUnwrap(viewModel.rawBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(viewModel.displayedBPM), 120.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.tapCount, 2)
        XCTAssertEqual(try fixture.store.listEntries(), [])
    }

    // B1: a new Save backs up the bad bytes, then succeeds on fresh history.
    func testSaveAfterCorruptionBacksUpAndSucceeds() throws {
        let fixture = CorruptHistoryFixture()
        let viewModel = BPMTapperViewModel(
            historyStore: fixture.store,
            clipboard: FakeClipboard()
        )
        tap120BPM(on: viewModel)
        XCTAssertThrowsError(try viewModel.loadHistory())

        viewModel.saveDisplayedBPM()

        XCTAssertEqual(viewModel.saveConfirmation, "BPM saved")
        XCTAssertNil(viewModel.errorText)
        XCTAssertFalse(viewModel.hasCorruptHistory)
        XCTAssertEqual(viewModel.historyEntries.count, 1)
        XCTAssertEqual(
            fixture.preferences.data(forKey: fixture.store.corruptBackupKey),
            Data("{not-json".utf8),
            "the unreadable payload must survive under the quarantine key"
        )
    }

    func testCorruptErrorPersistsAcrossTapResetAndCopy() throws {
        let fixture = CorruptHistoryFixture()
        let clipboard = FakeClipboard()
        let viewModel = BPMTapperViewModel(
            historyStore: fixture.store,
            clipboard: clipboard
        )
        XCTAssertThrowsError(try viewModel.loadHistory())
        XCTAssertEqual(viewModel.errorText, BPMTapperViewModel.corruptHistoryMessage)

        viewModel.recordTap(at: 0.0)
        viewModel.recordTap(at: 0.5)
        XCTAssertEqual(viewModel.errorText, BPMTapperViewModel.corruptHistoryMessage)
        XCTAssertTrue(viewModel.hasCorruptHistory)

        viewModel.copyDisplayedBPM()
        XCTAssertEqual(viewModel.errorText, BPMTapperViewModel.corruptHistoryMessage)

        viewModel.resetTaps()
        XCTAssertEqual(viewModel.errorText, BPMTapperViewModel.corruptHistoryMessage)
        XCTAssertTrue(viewModel.hasCorruptHistory)
    }

    func testClearHistoryFromCorruptionBacksUpBadBytes() throws {
        let fixture = CorruptHistoryFixture()
        let viewModel = BPMTapperViewModel(
            historyStore: fixture.store,
            clipboard: FakeClipboard()
        )
        tap120BPM(on: viewModel)
        XCTAssertThrowsError(try viewModel.loadHistory())

        viewModel.clearHistory()

        XCTAssertNil(viewModel.errorText)
        XCTAssertFalse(viewModel.hasCorruptHistory)
        XCTAssertEqual(
            fixture.preferences.data(forKey: fixture.store.corruptBackupKey),
            Data("{not-json".utf8),
            "confirmed Clear must preserve the exact malformed bytes"
        )
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

private struct FlakyHistoryStoreError: Error {}

/// Isolated `UserDefaults` preference store pre-seeded with invalid BPM
/// history bytes, so view-model recovery is exercised end to end.
private struct CorruptHistoryFixture {
    let store: UserDefaultsBPMHistoryStore
    let preferences: UserDefaultsPreferenceStore

    init() {
        let suiteName = "OutsideCubaseHubBPMCorruptTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        preferences.set(
            Data("{not-json".utf8),
            forKey: "outsideCubaseHub.bpmHistory"
        )
        self.preferences = preferences
        self.store = UserDefaultsBPMHistoryStore(preferences: preferences)
    }
}

private final class FlakyHistoryStore: BPMHistoryStore, @unchecked Sendable {
    private(set) var entries: [BPMHistoryEntry] = []
    var failAdds = true

    func listEntries() throws -> [BPMHistoryEntry] {
        entries
    }

    func addEntry(_ entry: BPMHistoryEntry) throws {
        if failAdds { throw FlakyHistoryStoreError() }
        entries.insert(entry, at: 0)
    }

    func clearEntries() throws {
        entries = []
    }
}
