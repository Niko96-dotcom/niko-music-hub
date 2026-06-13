import AppCore
import FeatureBPMTapper
import XCTest

final class BPMHistoryStoreTests: XCTestCase {
    func testStartsEmpty() throws {
        let store = makeStore(reset: true)

        XCTAssertEqual(try store.listEntries(), [])
    }

    func testPersistsSavedEntry() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        let entry = BPMHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            bpm: 128.0,
            rawTappedBPM: 128.0,
            adjustment: .original,
            timestamp: Date(timeIntervalSince1970: 10)
        )

        try store.addEntry(entry)

        let reloaded = makeStore(suiteName: suiteName)
        XCTAssertEqual(try reloaded.listEntries(), [entry])
    }

    func testNewestEntriesAppearFirst() throws {
        let store = makeStore(reset: true)
        let older = BPMHistoryEntry(
            bpm: 100.0,
            rawTappedBPM: 200.0,
            adjustment: .halfTime,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let newer = BPMHistoryEntry(
            bpm: 130.0,
            rawTappedBPM: 65.0,
            adjustment: .doubleTime,
            timestamp: Date(timeIntervalSince1970: 20)
        )

        try store.addEntry(older)
        try store.addEntry(newer)

        XCTAssertEqual(try store.listEntries(), [newer, older])
    }

    func testClearEntriesRemovesSavedHistory() throws {
        let store = makeStore(reset: true)
        try store.addEntry(BPMHistoryEntry(
            bpm: 128.0,
            rawTappedBPM: 128.0,
            adjustment: .original,
            timestamp: Date(timeIntervalSince1970: 10)
        ))

        try store.clearEntries()

        XCTAssertEqual(try store.listEntries(), [])
    }

    func testPersistsSavedEntryThroughPreferenceStore() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        let store = UserDefaultsBPMHistoryStore(preferences: preferences)
        let entry = BPMHistoryEntry(
            bpm: 90,
            rawTappedBPM: 180,
            adjustment: .halfTime,
            timestamp: Date(timeIntervalSince1970: 30)
        )

        try store.addEntry(entry)

        let reloaded = UserDefaultsBPMHistoryStore(preferences: preferences)
        XCTAssertEqual(try reloaded.listEntries(), [entry])
    }

    func testBPMTapperFeatureUsesContextPreferences() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureBPMTapper/BPMTapperFeature.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("context.preferences"))
        XCTAssertFalse(source.contains("UserDefaultsBPMHistoryStore()"))
    }

    private func makeStore(
        suiteName: String = UUID().uuidString,
        reset: Bool = false
    ) -> UserDefaultsBPMHistoryStore {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        if reset {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return UserDefaultsBPMHistoryStore(userDefaults: userDefaults)
    }

    private func uniqueSuiteName() -> String {
        "OutsideCubaseHubBPMHistoryTests.\(UUID().uuidString)"
    }
}
